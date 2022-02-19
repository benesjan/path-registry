// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "./interfaces/IQuoter.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/ICachedRouter.sol";

contract CachedRouter is ICachedRouter {
    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function registerPath(bytes calldata path, uint256 amountIn) external override {
        uint256 amountOut = QUOTER.quoteExactInput(path, amountIn);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external payable override returns (uint256 amountOut) {}
}
