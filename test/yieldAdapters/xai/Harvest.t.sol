// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./BaseArbSepolia.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract HarvestTest is XaiBaseTest {
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

    function test_Harvest() external {
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

        /* Validate state */
        assertEq(yieldPass.claimableYield(yp), 2, "Invalid claimable yield");
        assertEq(yieldPass.cumulativeYield(yp), 2, "Invalid cumulative yield");
        assertEq(IERC20(esXai).balanceOf(address(yieldAdapter)), 2, "Invalid esXAI balance");
        assertEq(yieldPass.yieldPassShares(yp), 1 ether, "Invalid total shares state");
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

    function test__Harvest_RevertWhen_HarvestCompleted() external {
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

        /* Fast-forward to 1 second before expiry */
        vm.warp(expiry - 1);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        yieldPass.harvest(yp, "");

        /* Fast-forward to 1 second after expiry */
        vm.warp(expiry + 1);

        /* Harvest yield */
        yieldPass.harvest(yp, "");

        /* Fast-forward to 10 seconds after expiry */
        vm.warp(expiry + 10);

        /* Expect revert */
        vm.expectRevert(abi.encodeWithSelector(XaiYieldAdapter.HarvestCompleted.selector));
        yieldPass.harvest(yp, "");
        vm.stopPrank();
    }
}
