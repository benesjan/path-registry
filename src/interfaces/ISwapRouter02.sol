// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Router token swapping functionality
interface ISwapRouter02 {
    // Uniswap v2
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    // Uniswap v3
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
