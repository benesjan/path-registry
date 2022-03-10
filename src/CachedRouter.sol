// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "./libs/BytesLib.sol";
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

    mapping(address => mapping(address => uint256)) public pathBeginnings;

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
        // TODO: handle path deletion and implement path amount limit
        // First check whether path has been initialized
        address tokenIn;
        address tokenOut;
        if (newPath.subPathsV2.length != 0) {
            tokenIn = newPath.subPathsV2[0].path[0];
            tokenOut = newPath.subPathsV2[newPath.subPathsV2.length - 1].path[1];
        } else if (newPath.subPathsV3.length != 0) {
            bytes calldata v3Path = newPath.subPathsV3[0].path;
            tokenIn = v3Path.toAddress(0);
            tokenOut = v3Path.toAddress(v3Path.length - 20);
        } else {
            require(false, "CachedRouter: EMPTY_PATH");
        }

        uint256 curPathIndex = pathBeginnings[tokenIn][tokenOut];
        if (curPathIndex == 0) {
            require(newPath.amount == 0, "CachedRouter: NON_ZERO_AMOUNT");
            // TODO: check percent sum == 0
            allPaths.push(newPath);
            pathBeginnings[tokenIn][tokenOut] = allPaths.length - 1;

            require(IERC20(tokenIn).approve(address(ROUTER), type(uint256).max), "CachedRouter: APPROVE_FAILED");
        } else {
            require(newPath.amount != 0, "CachedRouter: ZERO_AMOUNT");
            // Note: Here newPath is copied from calldata to memory. I can't pass calldata directly to this function
            // because later on I need to pass a storage struct (curPath) and it's impossible to copy from storage
            // to calldata.
            uint256 newPathQuote = quotePath(newPath, newPath.amount);

            bool notInserted = true;
            while (notInserted) {
                Path memory curPath = allPaths[curPathIndex];
                Path memory nextPath = allPaths[curPath.next];
                if (curPath.next == 0 || newPath.amount < nextPath.amount) {
                    uint256 curPathQuote = quotePath(curPath, newPath.amount);
                    require(curPathQuote < newPathQuote, "CachedRouter: QUOTE_NOT_BETTER");
                    insertPath(newPath, curPathIndex, curPath.next);
                    notInserted = false;
                }
                curPathIndex = curPath.next;
            }
            require(!notInserted, "CachedRouter: PATH_NOT_INSERTED");
        }
    }

    // TODO: memory or calldata here
    function quotePath(Path memory path, uint256 amountIn) private returns (uint256 amountOut) {
        uint256 subAmountIn;
        uint256 percentSum;

        for (uint256 i; i < path.subPathsV2.length; i++) {
            SubPathV2 memory subPath = path.subPathsV2[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QOUTER_V2.getAmountsOut(subAmountIn, subPath.path)[subPath.path.length - 1];
            percentSum += subPath.percent;
        }

        for (uint256 i; i < path.subPathsV3.length; i++) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            percentSum += subPath.percent;
        }

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

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable returns (uint256 amountOut) {
        uint256 curPathIndex = pathBeginnings[tokenIn][tokenOut];
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
                for (uint256 i; i < curPath.subPathsV2.length; i++) {
                    SubPathV2 memory subPath = curPath.subPathsV2[i];
                    subAmountIn = (amountIn * subPath.percent) / 100;
                    amountOut += ROUTER.swapExactTokensForTokens(subAmountIn, 0, subPath.path, msg.sender);
                }

                for (uint256 i; i < curPath.subPathsV3.length; i++) {
                    SubPathV3 memory subPath = curPath.subPathsV3[i];
                    subAmountIn = (amountIn * subPath.percent) / 100;
                    amountOut += ROUTER.exactInput(
                        ISwapRouter02.ExactInputParams(subPath.path, msg.sender, subAmountIn, 0)
                    );
                }
                break;
            }
            curPathIndex = curPath.next;
        }
        require(amountOutMin <= amountOut, "CachedRouter: INSUFFICIENT_AMOUNT_OUT");
    }
}
