// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract HarvestTest is XaiBaseTest {
    address internal yp;
    address internal dp;
    uint256[] internal tokenIds;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, dp) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds = new uint256[](1);
        tokenIds[0] = 19727;
    }

    function simulateYieldDistributionInStakingPool() internal {
        uint256 beforeBalance = esXai.balanceOf(address(stakingPool));

        vm.startPrank(esXaiOwner);
        esXai.transfer(address(stakingPool), 10000);
        vm.stopPrank();

        uint256 afterBalance = esXai.balanceOf(address(stakingPool));
        assertEq(afterBalance, beforeBalance + 10000, "Invalid balance");
    }

    function test_Harvest() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(
            yp, snlOwner, tokenIds, snlOwner, snlOwner, block.timestamp, generateStakingPools(stakingPool), ""
        );
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

        /* Validate state */
        assertEq(yieldPass.claimable(yp, 1 ether), 10, "Invalid claimable yield");
        assertEq(IERC20(esXai).balanceOf(address(yieldAdapter)), 10, "Invalid esXAI balance");

        assertEq(yieldPass.claimState(yp).total, 10, "Invalid total yield state");
        assertEq(yieldPass.claimState(yp).shares, 1 ether, "Invalid total shares state");
        assertEq(yieldPass.claimState(yp).balance, 10, "Invalid yield balance state");
    }

    function test__Harvest_RevertWhen_UndeployedYieldPass() external {
        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

        /* Harvest yield */
        vm.startPrank(users.deployer);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.harvest(randomAddress, "");
        vm.stopPrank();
    }
}
