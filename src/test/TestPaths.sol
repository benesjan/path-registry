// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "../CachedRouter.sol";

contract TestPaths {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    address private constant RANDOM_ADDRESS = 0xd2f4F51e80E2e857E32Dd8e7e2fcB30e498F71F0;

    function getPath1(uint256 amount) internal pure returns (CachedRouter.Path memory path) {
        path.amount = amount;
        path.subPathsV3 = new CachedRouter.SubPathV3[](1);

        path.subPathsV3[0] = CachedRouter.SubPathV3({
            percent: 100,
            path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), LUSD)
        });
    }

    function getPath2(uint256 amount) internal pure returns (CachedRouter.Path memory path) {
        path.amount = amount;
        path.subPathsV2 = new CachedRouter.SubPathV2[](1);
        path.subPathsV3 = new CachedRouter.SubPathV3[](3);

        // 1.
        address[] memory subPath1Addresses = new address[](2);
        subPath1Addresses[0] = WETH;
        subPath1Addresses[1] = LUSD;
        path.subPathsV2[0] = CachedRouter.SubPathV2({percent: 45, path: subPath1Addresses});

        // 2.
        path.subPathsV3[0] = CachedRouter.SubPathV3({percent: 45, path: abi.encodePacked(WETH, uint24(3000), LUSD)});

        // 3.
        path.subPathsV3[1] = CachedRouter.SubPathV3({
            percent: 5,
            path: abi.encodePacked(WETH, uint24(3000), DAI, uint24(3000), LUSD)
        });

        // 4.
        path.subPathsV3[2] = CachedRouter.SubPathV3({
            percent: 5,
            path: abi.encodePacked(WETH, uint24(10000), DAI, uint24(100), USDC, uint24(500), LUSD)
        });
    }

    function getBrokenPathUniV2(uint256 amount) internal pure returns (CachedRouter.Path memory path) {
        path.amount = amount;
        path.subPathsV2 = new CachedRouter.SubPathV2[](1);

        // 1.
        address[] memory subPath1Addresses = new address[](3);
        subPath1Addresses[0] = WETH;
        subPath1Addresses[1] = RANDOM_ADDRESS;
        subPath1Addresses[2] = LUSD;
        path.subPathsV2[0] = CachedRouter.SubPathV2({percent: 100, path: subPath1Addresses});
    }

    function getBrokenPathUniV3(uint256 amount) internal pure returns (CachedRouter.Path memory path) {
        path.amount = amount;
        path.subPathsV3 = new CachedRouter.SubPathV3[](1);

        path.subPathsV3[0] = CachedRouter.SubPathV3({
        percent: 100,
        path: abi.encodePacked(WETH, uint24(500), RANDOM_ADDRESS, uint24(500), LUSD)
        });
    }
}
