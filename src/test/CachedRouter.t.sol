// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0;

import "ds-test/test.sol";
import "../CachedRouter.sol";

contract CachedRouterTest is DSTest {
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    CachedRouter private cachedRouter;

    function setUp() public {
        cachedRouter = new CachedRouter();
    }

    function testRegisterPathNon0First() public {
        CachedRouter.Path memory path = getTestPath();
        path.amount = 5;
        try cachedRouter.registerPath(path) {
            assertTrue(false, "registerPath(..) has to revert when initializing path with non-zero amount.");
        } catch Error(string memory reason) {
            assertEq(reason, "CachedRouter: NON_ZERO_AMOUNT");
        }
    }

    function testRegisterPath() public {
        cachedRouter.registerPath(getTestPath());
        // TODO
    }

    function getTestPath() private pure returns (CachedRouter.Path memory path) {
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
}
