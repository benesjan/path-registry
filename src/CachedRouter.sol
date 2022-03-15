// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "./libs/BytesLib.sol";
import "./libs/OracleLibrary.sol";

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IQuoter.sol";
import "./interfaces/ISwapRouter02.sol";
import "./interfaces/IUniswapV2Router01.sol";

contract CachedRouter {
    using BytesLib for bytes;

    IUniswapV2Router01 public constant QOUTER_V2 = IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IQuoter public constant QUOTER_V3 = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter02 public constant ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => mapping(address => uint256)) public firstPathIndices;

    struct SubPathV2 {
        uint256 percent; // No packing here so I am using uint256 to avoid runtime conversion from uint8 to uint256
        address[] path;
    }

    struct SubPathV3 {
        uint256 percent;
        bytes path;
    }

    struct Path {
        uint256 amount; // Amount at which the path starts being valid
        uint256 next;
        SubPathV2[] subPathsV2;
        SubPathV3[] subPathsV3;
    }

    Path[] public allPaths;

    constructor() {
        // Waste the first array element in order to be able to check uninitialized Path by index == 0
        allPaths.push();
    }

    function registerPath(Path calldata newPath) external {
        (address tokenIn, address tokenOut) = getTokenInOut(newPath);
        uint256 prevPathIndex = firstPathIndices[tokenIn][tokenOut];

        if (prevPathIndex == 0) {
            require(newPath.amount == 0, "CachedRouter: NON_ZERO_AMOUNT");
            // TODO: check percent sum == 0
            // An unviable path might be provided since I am not quoting during first registration - make sure quotePath
            // returns 0 when the swap fails
            allPaths.push(newPath);
            firstPathIndices[tokenIn][tokenOut] = allPaths.length - 1;

            require(IERC20(tokenIn).approve(address(ROUTER), type(uint256).max), "CachedRouter: APPROVE_FAILED");
        } else {
            require(newPath.amount != 0, "CachedRouter: ZERO_AMOUNT");

            // Find the position where the new path should be inserted
            Path memory prevPath = allPaths[prevPathIndex];
            Path memory nextPath = allPaths[prevPath.next];
            while (prevPath.next != 0 || newPath.amount < nextPath.amount) {
                prevPathIndex = prevPath.next;
                prevPath = nextPath;
                nextPath = allPaths[prevPath.next];
            }

            // Verify that newPath's quote is better at newPath.amount than prevPath's
            require(
                quotePath(prevPath, newPath.amount, tokenOut) < quotePath(newPath, newPath.amount, tokenOut),
                "CachedRouter: QUOTE_NOT_BETTER"
            );

            if (
                prevPath.next != 0 &&
                quotePath(newPath, nextPath.amount, tokenOut) > quotePath(nextPath, nextPath.amount, tokenOut)
            ) {
                // Replace next paths if the new path is better
                allPaths[prevPath.next] = newPath;
                allPaths[prevPath.next].next = nextPath.next;
                // TODO: try removing following paths or is it too expensive?
            } else {
                // Insert new path between prevPath and nextPath
                allPaths.push(newPath);
                uint256 newPathIndex = allPaths.length - 1;
                allPaths[prevPathIndex].next = newPathIndex;
                allPaths[newPathIndex].next = prevPath.next;
            }
        }
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        require(curPathIndex != 0, "CachedRouter: PATH_NOT_INITIALIZED");

        if (msg.value > 0) {
            require(tokenIn == WETH, "CachedRouter: NON_WETH_INPUT");
            require(msg.value == amountIn, "CachedRouter: INCORRECT_AMOUNT_IN");
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "CachedRouter: TRANSFER_FAILED");
        }

        while (true) {
            Path memory curPath = allPaths[curPathIndex];
            Path memory nextPath = allPaths[curPath.next];
            if (curPath.next == 0 || amountIn < nextPath.amount) {
                uint256 subAmountIn;
                uint256 arrayLength = curPath.subPathsV2.length;
                for (uint256 i; i < arrayLength; ) {
                    SubPathV2 memory subPath = curPath.subPathsV2[i];
                    subAmountIn = (amountIn * subPath.percent) / 100;
                    amountOut += ROUTER.swapExactTokensForTokens(subAmountIn, 0, subPath.path, msg.sender);
                    unchecked {
                        ++i;
                    }
                }

                arrayLength = curPath.subPathsV3.length;
                for (uint256 i; i < arrayLength; ) {
                    SubPathV3 memory subPath = curPath.subPathsV3[i];
                    subAmountIn = (amountIn * subPath.percent) / 100;
                    amountOut += ROUTER.exactInput(
                        ISwapRouter02.ExactInputParams(subPath.path, msg.sender, subAmountIn, 0)
                    );
                    unchecked {
                        ++i;
                    }
                }
                break;
            }
            curPathIndex = curPath.next;
        }
        require(amountOutMin <= amountOut, "CachedRouter: INSUFFICIENT_AMOUNT_OUT");
    }

    // TODO: memory or calldata here
    // Note: Gas consumption might be reduced by quoting Uni V3 price using OracleLibrary:
    // https://github.com/Uniswap/v3-periphery/blob/51f8871aaef2263c8e8bbf4f3410880b6162cdea/contracts/libraries/OracleLibrary.sol#L49
    // - less gas would be consumed but it would be less precise as it assumes no ticks will be crossed
    // - it would also make estimation of swap gas cost more difficult
    function quotePath(
        Path memory path,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        uint256 subAmountIn;
        uint256 percentSum;

        uint256 gasLeftBefore = gasleft();
        uint256 arrayLength = path.subPathsV2.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV2 memory subPath = path.subPathsV2[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QOUTER_V2.getAmountsOut(subAmountIn, subPath.path)[subPath.path.length - 1];
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }

        arrayLength = path.subPathsV3.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }
        // Note: this value does not precisely represent gas consumed during swaps since swaps are not exactly equal
        // to quoting. However it should be a good enough approximation.
        uint256 weiConsumed = (gasLeftBefore - gasleft()) * tx.gasprice;
        uint256 tokenConsumed = OracleLibrary.getQuoteAtCurrentTick(weiConsumed, tokenOut);
        amountOut = (amountOut > tokenConsumed) ? amountOut - tokenConsumed : 0;

        require(percentSum == 100, "CachedRouter: INCORRECT_PERC_SUM");
    }

    function insertPath(
        Path calldata newPath,
        uint256 curPathIndex,
        uint256 nextPathIndex
    ) private {
        allPaths.push(newPath);
        uint256 newPathIndex = allPaths.length - 1;
        allPaths[curPathIndex].next = newPathIndex;
        allPaths[newPathIndex].next = nextPathIndex;
    }

    function getTokenInOut(Path memory path) private pure returns (address tokenIn, address tokenOut) {
        if (path.subPathsV2.length != 0) {
            tokenIn = path.subPathsV2[0].path[0];
            tokenOut = path.subPathsV2[path.subPathsV2.length - 1].path[1];
        } else if (path.subPathsV3.length != 0) {
            bytes memory v3Path = path.subPathsV3[0].path;
            tokenIn = v3Path.toAddress(0);
            tokenOut = v3Path.toAddress(v3Path.length - 20);
        } else {
            require(false, "CachedRouter: EMPTY_PATH");
        }
    }
}
