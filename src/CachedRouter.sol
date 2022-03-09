// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "./libs/BytesLib.sol";
import "./interfaces/IQuoter.sol";
import "./interfaces/IUniswapV2Router01.sol";

contract CachedRouter {
    using BytesLib for bytes;

    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IUniswapV2Router01 public constant ROUTER_V2 = IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    mapping(address => mapping(address => uint256)) public pathBeginnings;

    //    ISwapRouter02 public constant ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

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
        // First check whether path has been initialized
        address input;
        address output;
        if (newPath.subPathsV2.length != 0) {
            input = newPath.subPathsV2[0].path[0];
            output = newPath.subPathsV2[newPath.subPathsV2.length - 1].path[1];
        } else if (newPath.subPathsV3.length != 0) {
            bytes calldata v3Path = newPath.subPathsV3[0].path;
            input = v3Path.toAddress(0);
            output = v3Path.toAddress(v3Path.length - 20);
        } else {
            require(false, "CachedRouter: EMPTY_PATH");
        }

        uint256 curPathIndex = pathBeginnings[input][output];
        if (curPathIndex == 0) {
            require(newPath.amount == 0, "CachedRouter: NON_ZERO_AMOUNT");
            allPaths.push(newPath);
            pathBeginnings[input][output] = allPaths.length - 1;
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
            amountOut += ROUTER_V2.getAmountsOut(subAmountIn, subPath.path)[subPath.path.length - 1];
            percentSum += subPath.percent;
        }

        for (uint256 i; i < path.subPathsV3.length; i++) {
            SubPathV3 memory subPath = path.subPathsV3[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER.quoteExactInput(subPath.path, subAmountIn);
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
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
        //        bytes memory path = bytes(""); // TODO: fetch path
        //        amountOut = ROUTER.exactInput(ISwapRouter02.ExactInputParams(path, msg.sender, block.timestamp, amountIn, 0));
    }
}
