// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.7.5;

import "uni-interfaces/IQuoter.sol";
import "uni-interfaces/ISwapRouter02.sol";
import "./interfaces/ICachedRouter.sol";

contract CachedRouter is ICachedRouter {
    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter02 public constant ROUTER = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    function registerPath(bytes calldata path, uint256 amountIn) external override {
        uint256 amountOut = QUOTER.quoteExactInput(path, amountIn);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external payable override returns (uint256 amountOut) {}
}
