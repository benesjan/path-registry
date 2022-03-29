// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

/**
 * @title A contract allowing for registration of paths and token swapping on Uniswap v2 and v3
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to register a path and then to swap tokens using the registered paths
 * @dev This smart contract has 2 functions:
 *      1. A registration and a quality verification of Uniswap v2 and v3 paths
 *      2. Swapping tokens using the registered paths - a path is selected based on the input and output token addresses
 *         and the amount of input token to swap
 *
 *      For each registered tokenIn-tokenOut pair there is a linked list of Path structs sorted by amount in
 *      an ascending order. This linked list can be iterated through using the next parameter. Each path is valid
 *      in a range [path.amount, nextPath.amount). If path.next doesn't exist, the path is valid
 *      in [path.amount, infinity).
 */
interface IPathRegistry {
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
        uint256 next; // Index of the next path
        SubPathV2[] subPathsV2;
        SubPathV3[] subPathsV3;
    }

    /**
     * @notice Verifies and registers a new path
     * @param newPath A path to register (newPath.next parameter is irrelevant because it's computed later on)
     * @dev Reverts when the new path doesn't have a better quote than the previous path at newPath.amount
     */
    function registerPath(Path calldata newPath) external;

    /**
     * @notice Selects a path based on `tokenIn`, `tokenOut` and `amountIn` and swaps `amountIn` of `tokenIn` for
     * as much as possible of `tokenOut` along the selected path
     * @param tokenIn An address of a token to sell
     * @param tokenOut An address of a token to buy
     * @param amountIn An amount of `tokenIn` to swap
     * @param amountOutMin Minimum amount of tokenOut to receive (inactive when set to 0)
     * @return amountOut An amount of token received
     * @dev Reverts when a path is not found
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Selects a path based on `tokenIn`, `tokenOut` and `amountIn` and computes a quote for `amountIn`
     * @param tokenIn An address of a token to sell
     * @param tokenOut An address of a token to buy
     * @param amountIn An amount of `tokenIn` to get a quote for
     * @return amountOut An amount of token received
     * @dev Reverts when a path is not found. Not marked as view because Uni v3 quoter modifies states and then reverts.
     */
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}
