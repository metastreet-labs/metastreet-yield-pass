// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TestYieldAdapterBaseTest} from "./Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

contract HarvestTest is TestYieldAdapterBaseTest {
    uint256[] internal tokenIds1;

    function setUp() public override {
        /* Set up */
        TestYieldAdapterBaseTest.setUp();

        tokenIds1 = new uint256[](2);
        tokenIds1[0] = 0;
        tokenIds1[1] = 1;
    }

    function test_Harvest() external {
        /* Mint */
        vm.startPrank(users.normalUser1);
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");
        vm.stopPrank();

        /* Fast-forward to two days after start */
        vm.warp(startTime + 2 * 86400);

        /* Harvest yield */
        vm.startPrank(users.normalUser2);
        uint256 yieldAmount = yieldPass.harvest(yp, "");
        vm.stopPrank();

        /* Yield amount should be between 4.0-6.0 */
        assertGt(yieldAmount, 4 ether, "Invalid yield amount");
        assertLt(yieldAmount, 6 ether, "Invalid yield amount");

        /* Validate state */
        assertEq(yieldPass.claimableYield(yp), yieldAmount, "Invalid claimable yield");
        assertEq(yieldPass.cumulativeYield(yp), yieldAmount, "Invalid cumulative yield");
        assertEq(testYieldToken.balanceOf(address(yieldAdapter)), yieldAmount, "Invalid yield token balance");
        assertEq(yieldPass.yieldPassShares(yp), 2 ether, "Invalid total shares state");
    }
}
