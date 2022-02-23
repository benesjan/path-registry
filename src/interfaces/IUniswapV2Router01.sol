pragma solidity ^0.8.0;

interface IUniswapV2Router01 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}
