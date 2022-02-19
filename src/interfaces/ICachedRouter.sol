// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

interface ICachedRouter {
    function registerPath(bytes calldata path, uint256 amountIn) external;

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external payable returns (uint256 amountOut);
}
