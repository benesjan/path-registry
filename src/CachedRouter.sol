// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.7.5;
pragma abicoder v2;

import "uni-interfaces/IQuoter.sol";
import "uni-interfaces/ISwapRouter02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

contract CachedRouter {
    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IUniswapV2Router01 public constant ROUTER_V2 = IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ISwapRouter02 public constant ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    struct SubPathV2 {
        uint8 percent;
        address[] path;
    }

    struct SubPathV3 {
        uint8 percent;
        bytes path;
    }

    struct Path {
        SubPathV2[] subPathsV2;
        SubPathV3[] subPathsV3;
    }

    function registerPath(Path calldata path, uint256 amountIn) external {
        uint256 amountOut;
        uint256 subAmountIn;
        uint8 percentSum;

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

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
//        bytes memory path = bytes(""); // TODO: fetch path
//        amountOut = ROUTER.exactInput(ISwapRouter02.ExactInputParams(path, msg.sender, block.timestamp, amountIn, 0));
    }
}
