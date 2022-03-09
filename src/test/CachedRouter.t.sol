// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.0;

import "ds-test/test.sol";
import "./TestPaths.sol";
import "../CachedRouter.sol";

contract CachedRouterTest is DSTest {
    TestPaths private testPaths;
    CachedRouter private cachedRouter;

    function setUp() public {
        testPaths = new TestPaths();
        cachedRouter = new CachedRouter();
    }

    function testRegisterPathNon0First() public {
        try cachedRouter.registerPath(testPaths.getPath1(5)) {
            assertTrue(false, "registerPath(..) has to revert when initializing path with non-zero amount.");
        } catch Error(string memory reason) {
            assertEq(reason, "CachedRouter: NON_ZERO_AMOUNT");
        }
    }

    function testRegisterPath() public {
        cachedRouter.registerPath(testPaths.getPath1(0));
        cachedRouter.registerPath(testPaths.getPath2(1e22)); // 10000 ETH

        (uint256 amount1, uint256 next1) = cachedRouter.allPaths(1);
        assertEq(amount1, 0);
        assertEq(next1, 2);

        (uint256 amount2, uint256 next2) = cachedRouter.allPaths(2);
        assertEq(amount2, 1e22);
        assertEq(next2, 0);
    }
}
