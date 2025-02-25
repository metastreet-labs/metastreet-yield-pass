// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./BaseArbSepolia.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract ClaimTest is XaiBaseTest {
    address internal yp;
    address internal np;
    uint256[] internal tokenIds;
    address[] internal stakingPools1;
    uint256[] internal quantities1;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, np) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds = new uint256[](1);
        tokenIds[0] = 123714;

        stakingPools1 = new address[](1);
        stakingPools1[0] = stakingPool1;

        quantities1 = new uint256[](1);
        quantities1[0] = 1;
    }

    function simulateYieldDistributionInStakingPool() internal {
        uint256 beforeBalance = esXai.balanceOf(address(stakingPool1));

        vm.startPrank(esXaiOwner);
        esXai.transfer(address(stakingPool1), 10000);
        vm.stopPrank();

        uint256 afterBalance = esXai.balanceOf(address(stakingPool1));
        assertEq(afterBalance, beforeBalance + 10000, "Invalid balance");
    }

    function test__Claim() external {
        /* Get user initial esXAI balance */
        uint256 initialBalance = esXai.balanceOf(snlOwner1);

        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds,
            generateStakingPools(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 2, "Invalid yield amount");
        vm.stopPrank();

        /* Claim */
        vm.startPrank(snlOwner1);
        yieldPass.claim(yp, snlOwner1, IERC20(yp).balanceOf(snlOwner1));
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 2, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 2, "Invalid cumulative yield");

        /* Check claimable yield */
        assertEq(yieldPass.claimableYield(yp), 2, "Invalid claimable yield");
        assertEq(yieldPass.claimableYield(yp, 1 ether), 2, "Invalid claimable yield");

        assertEq(IERC20(yp).balanceOf(snlOwner1), 0, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), 0, "Invalid total supply");
        assertEq(IERC20(esXai).balanceOf(snlOwner1), initialBalance + 2, "Invalid esXAI balance");
        assertEq(sentryNodeLicense.ownerOf(123714), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(123714), snlOwner1, "Invalid delegate token owner");

        assertEq(yieldPass.claimState(yp).total, 2, "Invalid total yield state");
        assertEq(yieldPass.claimState(yp).shares, 1 ether, "Invalid total shares state");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid yield balance state");
    }

    function test__Claim_RevertWhen_InvalidAmount() external {
        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds,
            generateStakingPools(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 2, "Invalid yield amount");
        vm.stopPrank();

        vm.startPrank(snlOwner1);

        /* Claim with 0 */
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, snlOwner1, 0);

        /* Claim with insufficient balance amount */
        uint256 userBalance = IERC20(yp).balanceOf(snlOwner1);
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, snlOwner1, userBalance + 1);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_InvalidClaimWindow() external {
        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds,
            generateStakingPools(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Fast-forward to after expiry */
        vm.warp(expiry);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 2, "Invalid yield amount");
        vm.stopPrank();

        /* Claim early */
        vm.startPrank(snlOwner1);
        uint256 userBalance = IERC20(yp).balanceOf(snlOwner1);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.claim(yp, snlOwner1, userBalance);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_HarvestNotCompleted() external {
        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds,
            generateStakingPools(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, "");
        assertEq(amount, 2, "Invalid yield amount");
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Claim early */
        vm.startPrank(snlOwner1);
        uint256 userBalance = IERC20(yp).balanceOf(snlOwner1);
        vm.expectRevert(IYieldAdapter.HarvestNotCompleted.selector);
        yieldPass.claim(yp, snlOwner1, userBalance);
        vm.stopPrank();
    }
}
