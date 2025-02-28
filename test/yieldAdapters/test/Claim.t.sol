// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TestYieldAdapterBaseTest} from "./Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

contract ClaimTest is TestYieldAdapterBaseTest {
    function setUp() public override {
        /* Set up */
        TestYieldAdapterBaseTest.setUp();

        uint256[] memory tokenIds1 = new uint256[](2);
        tokenIds1[0] = 0;
        tokenIds1[1] = 1;

        uint256[] memory tokenIds2 = new uint256[](3);
        tokenIds2[0] = 2;
        tokenIds2[1] = 3;
        tokenIds2[2] = 4;

        /* Mint */
        vm.startPrank(users.normalUser1);
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");
        vm.stopPrank();

        vm.startPrank(users.normalUser2);
        yieldPass.mint(yp, users.normalUser2, users.normalUser2, block.timestamp, tokenIds2, "");
        vm.stopPrank();
    }

    function test__Claim() external {
        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Harvest yield */
        vm.startPrank(users.normalUser2);
        uint256 yieldAmount = yieldPass.harvest(yp, "");
        vm.stopPrank();

        /* Claim */
        vm.startPrank(users.normalUser1);
        uint256 claimAmount = yieldPass.claim(yp, users.normalUser1, IERC20(yp).balanceOf(users.normalUser1));
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), yieldAmount, "Invalid cumulative yield");
        assertApproxEqAbs(
            yieldPass.cumulativeYield(yp, 2 ether), (yieldAmount * 2) / 5, 100, "Invalid cumulative yield"
        );

        /* Check claimable yield */
        assertEq(
            yieldPass.claimableYield(yp),
            IERC20(yieldAdapter.token()).balanceOf(address(yieldAdapter)),
            "Invalid claimable yield"
        );

        assertEq(IERC20(yp).balanceOf(users.normalUser1), 0, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), 3 ether, "Invalid total supply");
        assertEq(testYieldToken.balanceOf(users.normalUser1), claimAmount, "Invalid yield token balance");
        assertEq(testNodeLicense.ownerOf(0), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(0), users.normalUser1, "Invalid node pass owner");
        assertEq(testNodeLicense.ownerOf(1), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(1), users.normalUser1, "Invalid node pass owner");

        assertEq(yieldPass.yieldPassShares(yp), 5 ether, "Invalid total shares state");
    }

    function test__Claim_RevertWhen_InvalidAmount() external {
        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Harvest yield */
        vm.startPrank(users.normalUser2);
        yieldPass.harvest(yp, "");
        vm.stopPrank();

        vm.startPrank(users.normalUser1);

        /* Claim with 0 */
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, users.normalUser1, 0);

        /* Claim with insufficient yp amount */
        uint256 ypBalance = IERC20(yp).balanceOf(users.normalUser1);
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, users.normalUser1, ypBalance + 1);

        vm.stopPrank();
    }

    function test__Claim_RevertWhen_InvalidClaimWindow() external {
        /* Fast-forward to just at expiry */
        vm.warp(expiryTime);

        /* Harvest yield */
        vm.startPrank(users.normalUser2);
        yieldPass.harvest(yp, "");
        vm.stopPrank();

        /* Claim early */
        vm.startPrank(users.normalUser1);
        uint256 ypBalance = IERC20(yp).balanceOf(users.normalUser1);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.claim(yp, users.normalUser1, ypBalance);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_HarvestNotCompleted() external {
        /* Fast-forward to just before expiry */
        vm.warp(expiryTime - 10);

        /* Harvest yield */
        vm.startPrank(users.normalUser2);
        yieldPass.harvest(yp, "");
        vm.stopPrank();

        /* Fast-forward to just after expiry */
        vm.warp(expiryTime + 1);

        /* Claim */
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IYieldAdapter.HarvestNotCompleted.selector);
        yieldPass.claim(yp, users.normalUser1, 1);
        vm.stopPrank();
    }
}
