// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract ClaimTest is XaiBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, dp) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function simulateYieldDistributionInStakingPool() internal {
        uint256 beforeBalance = esXai.balanceOf(address(stakingPool));

        vm.startPrank(esXaiOwner);
        esXai.transfer(address(stakingPool), 10000);
        vm.stopPrank();

        uint256 afterBalance = esXai.balanceOf(address(stakingPool));
        assertEq(afterBalance, beforeBalance + 10000, "Invalid balance");
    }

    function test__Claim() external {
        /* Get user initial esXAI balance */
        uint256 initialBalance = esXai.balanceOf(snlOwner);

        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 10, "Invalid yield amount");
        vm.stopPrank();

        /* Claim */
        vm.startPrank(snlOwner);
        yieldPass.claim(yp, IERC20(yp).balanceOf(snlOwner));
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 10, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 10, "Invalid cumulative yield");

        /* Check claimable yield */
        assertEq(yieldPass.claimable(yp, 1 ether), 10, "Invalid claimable yield");

        assertEq(IERC20(yp).balanceOf(snlOwner), 0, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), 0, "Invalid total supply");
        assertEq(IERC20(esXai).balanceOf(snlOwner), initialBalance + 10, "Invalid esXAI balance");
        assertEq(sentryNodeLicense.ownerOf(19727), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(19727), snlOwner, "Invalid delegate token owner");

        assertEq(yieldPass.claimState(yp).total, 10, "Invalid total yield state");
        assertEq(yieldPass.claimState(yp).shares, 1 ether, "Invalid total shares state");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid yield balance state");
    }

    function test__Claim_RevertWhen_InvalidAmount() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 10, "Invalid yield amount");
        vm.stopPrank();

        vm.startPrank(snlOwner);

        /* Claim with 0 */
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, 0);

        /* Claim with insufficient balance amount */
        uint256 userBalance = IERC20(yp).balanceOf(snlOwner);
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, userBalance + 1);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_InvalidClaimWindow() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 10, "Invalid yield amount");
        vm.stopPrank();

        /* Claim early */
        vm.startPrank(snlOwner);
        uint256 userBalance = IERC20(yp).balanceOf(snlOwner);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.claim(yp, userBalance);
        vm.stopPrank();
    }
}
