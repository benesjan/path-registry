// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import "./TestPaths.sol";
import "../CachedRouter.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IERC20.sol";

contract CachedRouterTest is DSTest, stdCheats, TestPaths {
    CachedRouter private cachedRouter;

    function setUp() public {
        cachedRouter = new CachedRouter();
    }

    function testRegisterPathNon0First() public {
        try cachedRouter.registerPath(getPath1(5)) {
            assertTrue(false, "registerPath(..) has to revert when initializing path with non-zero amount.");
        } catch Error(string memory reason) {
            assertEq(reason, "CachedRouter: NON_ZERO_AMOUNT");
        }
    }

    function testRegisterPath() public {
        cachedRouter.registerPath(getPath1(0));
        cachedRouter.registerPath(getPath2(1e22)); // 10000 ETH

        (uint256 amount1, uint256 next1) = cachedRouter.allPaths(1);
        assertEq(amount1, 0);
        assertEq(next1, 2);

        (uint256 amount2, uint256 next2) = cachedRouter.allPaths(2);
        assertEq(amount2, 1e22);
        assertEq(next2, 0);
    }

    function testSwapETH() public {
        cachedRouter.registerPath(getPath1(0));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e18;

        hoax(address(1337), amountIn);
        cachedRouter.swap{value: amountIn}(WETH, LUSD, amountIn, 0);
        assertGt(IERC20(LUSD).balanceOf(address(1337)), 0);
    }

    function testSwapERC20() public {
        cachedRouter.registerPath(getPath1(0));
        cachedRouter.registerPath(getPath2(1e22));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e18;

        startHoax(address(1337), amountIn);
        IWETH(WETH).deposit{value: amountIn}();
        IERC20(WETH).approve(address(cachedRouter), amountIn);

        cachedRouter.swap(WETH, LUSD, amountIn, 0);
        assertGt(IERC20(LUSD).balanceOf(address(1337)), 0);
    }

    function testSwapComplexPath() public {
        cachedRouter.registerPath(getPath1(0));
        cachedRouter.registerPath(getPath2(1e22));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e22;

        hoax(address(1337), amountIn);
        cachedRouter.swap{value: amountIn}(WETH, LUSD, amountIn, 0);
        assertGt(IERC20(LUSD).balanceOf(address(1337)), 0);
    }
}
