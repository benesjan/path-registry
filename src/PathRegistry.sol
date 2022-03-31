// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "./libs/BytesLib.sol";
import "./libs/UniLibSnippets.sol";

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IQuoter.sol";
import "./interfaces/IPathRegistry.sol";
import "./interfaces/ISwapRouter02.sol";
import "./interfaces/IUniswapV2Router01.sol";

// @inheritdoc IPathRegistry
contract PathRegistry is IPathRegistry {
    using BytesLib for bytes;

    IUniswapV2Router01 public constant QUOTER_V2 = IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IQuoter public constant QUOTER_V3 = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter02 public constant ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // @dev A mapping containing indices of the smallest amount paths
    mapping(address => mapping(address => uint256)) public firstPathIndices;

    // @dev An array used to store all the paths
    Path[] public allPaths;

    constructor() {
        // Waste the first array element in order to be able to check uninitialized Path by index == 0
        allPaths.push();
    }

    // @inheritdoc IPathRegistry
    function registerPath(Path calldata newPath) external override {
        (address tokenIn, address tokenOut) = getTokenInOut(newPath);
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        Path memory curPath = allPaths[curPathIndex];

        if (curPathIndex == 0) {
            require(UniLibSnippets.ethPoolExists(tokenOut), "NONEXISTENT_ETH_POOL");
            require(evaluatePath(newPath, newPath.amount, tokenOut) > 0, "UNVIABLE_PATH");

            allPaths.push(newPath);
            firstPathIndices[tokenIn][tokenOut] = allPaths.length - 1;

            require(IERC20(tokenIn).approve(address(ROUTER), type(uint256).max), "APPROVE_FAILED");
        } else if (newPath.amount < curPath.amount) {
            // New path should be inserted before the first path
            // Check whether newPath is better than the current first path at newPath.amount
            require(
                evaluatePath(curPath, newPath.amount, tokenOut) < evaluatePath(newPath, newPath.amount, tokenOut),
                "QUOTE_NOT_BETTER"
            );
            if (evaluatePath(curPath, curPath.amount, tokenOut) < evaluatePath(newPath, curPath.amount, tokenOut)) {
                // newPath is better even at curPath.amount - replace curPath with newPath
                allPaths[curPathIndex] = newPath;
                allPaths[curPathIndex].next = curPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (curPath.next != 0) prunePaths(curPathIndex, tokenOut);
            } else {
                // newPath is worse at curPath.amount - insert the path at the first position
                allPaths.push(newPath);
                uint256 pathIndex = allPaths.length - 1;
                allPaths[pathIndex].next = curPathIndex;
                firstPathIndices[tokenIn][tokenOut] = pathIndex;
            }
        } else {
            // Since newPath.amount > curPath.amount the path will not be inserted at the first position and for this
            // reason we have compute where the new path should be inserted
            Path memory nextPath = allPaths[curPath.next];
            while (curPath.next != 0 && newPath.amount > nextPath.amount) {
                curPathIndex = curPath.next;
                curPath = nextPath;
                nextPath = allPaths[curPath.next];
            }

            // Verify that newPath's quote is better at newPath.amount than prevPath's
            require(
                evaluatePath(curPath, newPath.amount, tokenOut) < evaluatePath(newPath, newPath.amount, tokenOut),
                "QUOTE_NOT_BETTER"
            );

            if (
                curPath.next != 0 &&
                evaluatePath(newPath, nextPath.amount, tokenOut) > evaluatePath(nextPath, nextPath.amount, tokenOut)
            ) {
                // newPath is better than nextPath at nextPath.amount - save newPath at nextPath index
                allPaths[curPath.next] = newPath;
                allPaths[curPath.next].next = nextPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (nextPath.next != 0) prunePaths(curPath.next, tokenOut);
            } else {
                // Insert new path between prevPath and nextPath
                allPaths.push(newPath);
                uint256 newPathIndex = allPaths.length - 1;
                allPaths[curPathIndex].next = newPathIndex;
                allPaths[newPathIndex].next = curPath.next;
            }
        }
    }

    // @inheritdoc IPathRegistry
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        require(curPathIndex != 0, "PATH_NOT_INITIALIZED");

        // 1. Convert ETH to WETH or transfer ERC20 to address(this)
        if (msg.value > 0) {
            require(tokenIn == WETH, "NON_WETH_INPUT");
            require(msg.value == amountIn, "INCORRECT_AMOUNT_IN");
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_FAILED");
        }

        // 2. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // 3. Swap
        uint256 subAmountIn;
        uint256 arrayLength = path.subPathsV2.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV2 memory subPath = path.subPathsV2[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += ROUTER.swapExactTokensForTokens(subAmountIn, 0, subPath.path, msg.sender);
            unchecked {
                ++i;
            }
        }

        arrayLength = path.subPathsV3.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += ROUTER.exactInput(ISwapRouter02.ExactInputParams(subPath.path, msg.sender, subAmountIn, 0));
            unchecked {
                ++i;
            }
        }

        require(amountOutMin <= amountOut, "INSUFFICIENT_AMOUNT_OUT");
    }

    // @inheritdoc IPathRegistry
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        require(curPathIndex != 0, "PATH_NOT_INITIALIZED");

        // 1. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // Get quote
        uint256 subAmountIn;
        uint256 arrayLength = path.subPathsV2.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV2 memory subPath = path.subPathsV2[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V2.getAmountsOut(subAmountIn, subPath.path)[subPath.path.length - 1];
            unchecked {
                ++i;
            }
        }

        arrayLength = path.subPathsV3.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Compares a given path with the following ones and if the following paths are worse deletes them
     * @param pathIndex An index of a path which will be compared with the paths that follow
     * @param tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @dev This method was implemented in order to keep the amount of stored paths low - this is very desirable
     * because paths are being iterated through during swap
     */
    function prunePaths(uint256 pathIndex, address tokenOut) private {
        Path memory path = allPaths[pathIndex];
        Path memory nextPath = allPaths[path.next];

        while (evaluatePath(nextPath, nextPath.amount, tokenOut) <= evaluatePath(path, nextPath.amount, tokenOut)) {
            delete allPaths[path.next];
            path.next = nextPath.next;
            allPaths[pathIndex].next = nextPath.next;
            nextPath = allPaths[path.next];
        }
    }

    /**
     * @notice Evaluates quality of a given path for `amountIn`
     * @param path A path to evaluate
     * @param amountIn An amount of tokenIn to get a quote for
     * @param tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @return score An integer measuring a quality of a path (higher is better)
     * @dev This method takes into consideration quote and gas consumed
     */
    function evaluatePath(
        Path memory path,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 score) {
        uint256 subAmountIn;
        uint256 percentSum;

        uint256 gasLeftBefore = gasleft();
        uint256 arrayLength = path.subPathsV2.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV2 memory subPath = path.subPathsV2[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            score += QUOTER_V2.getAmountsOut(subAmountIn, subPath.path)[subPath.path.length - 1];
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }

        arrayLength = path.subPathsV3.length;
        for (uint256 i; i < arrayLength; ) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            score += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }
        // Note: this value does not precisely represent gas consumed during swaps since swaps are not exactly equal
        // to quoting. However it should be a good enough approximation.
        uint256 weiConsumed = (gasLeftBefore - gasleft()) * tx.gasprice;
        // TODO: replace the following by calling Mean Finance's static oracle once the oracle is deployed
        uint256 tokenConsumed = UniLibSnippets.getQuoteAtCurrentTick(weiConsumed, tokenOut);
        score = (score > tokenConsumed) ? score - tokenConsumed : 0;

        require(percentSum == 100, "INCORRECT_PERC_SUM");
    }

    /**
     * @notice Returns input and output token from a multihop path
     * @param path A path from which the input and output token will be extracted
     * @return tokenIn Addresses of the first token in the path (input token)
     * @return tokenOut Addresses of the last token in the path (output token)
     */
    function getTokenInOut(Path memory path) private pure returns (address tokenIn, address tokenOut) {
        if (path.subPathsV2.length != 0) {
            tokenIn = path.subPathsV2[0].path[0];
            tokenOut = path.subPathsV2[path.subPathsV2.length - 1].path[1];
        } else if (path.subPathsV3.length != 0) {
            bytes memory v3Path = path.subPathsV3[0].path;
            tokenIn = v3Path.toAddress(0);
            tokenOut = v3Path.toAddress(v3Path.length - 20);
        } else {
            require(false, "EMPTY_PATH");
        }
    }
}
