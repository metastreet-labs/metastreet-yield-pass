// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./BaseArbSepolia.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {NodePassToken} from "src/NodePassToken.sol";
import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract XaiMintTest is XaiBaseTest {
    address internal yp;
    address internal np;
    uint256[] internal tokenIds1;
    uint256[] internal tokenIds2;
    uint256[] internal tokenIds3;
    uint256[] internal tokenIds4;
    address[] internal stakingPools1;
    address[] internal stakingPools2;
    uint256[] internal quantities1;
    uint256[] internal quantities2;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, np) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));

        /* Sentry node license owner of 123714, 123713, 123712, 123711, 122443, 122444, 122445 */
        tokenIds1 = new uint256[](1);
        tokenIds1[0] = 123714;

        tokenIds2 = new uint256[](2);
        tokenIds2[0] = 123713;
        tokenIds2[1] = 123712;

        tokenIds3 = new uint256[](2);
        tokenIds3[0] = 130606;
        tokenIds3[1] = 130605;
        tokenIds4 = new uint256[](1);
        tokenIds4[0] = 122443;

        stakingPools1 = new address[](1);
        stakingPools1[0] = stakingPool1;

        stakingPools2 = new address[](1);
        stakingPools2[0] = stakingPool2;

        quantities1 = new uint256[](1);
        quantities1[0] = 1;

        quantities2 = new uint256[](1);
        quantities2[0] = 2;
    }

    function simulateYieldDistributionInStakingPool() internal {
        uint256 beforeBalance = esXai.balanceOf(address(stakingPool1));

        vm.startPrank(esXaiOwner);
        esXai.transfer(address(stakingPool1), 10000);
        vm.stopPrank();

        uint256 afterBalance = esXai.balanceOf(address(stakingPool1));
        assertEq(afterBalance, beforeBalance + 10000, "Invalid balance");
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds1,
            generateStakingPools(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        uint256 expectedAmount1 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner1), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(123714), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(123714), snlOwner1, "Invalid node token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1, "Invalid claim state shares");

        /* Fast-forward to half-way point */
        vm.warp(startTime + ((expiry - startTime) / 2));

        /* Simulate yield distribution in staking pool */
        simulateYieldDistributionInStakingPool();

        /* Mint again */
        vm.startPrank(snlOwner1);
        (, uint256 harvestedAmount) = yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds2,
            generateStakingPools(stakingPools1, quantities2),
            ""
        );
        vm.stopPrank();

        uint256 expectedAmount2 = (2 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner1), expectedAmount1 + expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(123713), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(123713), snlOwner1, "Invalid delegate token owner");
        assertEq(sentryNodeLicense.ownerOf(123712), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(123712), snlOwner1, "Invalid delegate token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertGt(harvestedAmount, 0, "Invalid harvested amount");
        assertEq(yieldPass.claimState(yp).total, harvestedAmount, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, harvestedAmount, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1 + expectedAmount2, "Invalid claim state shares");
    }

    function test__Mint_RevertWhen_InvalidStakingPools() external {
        vm.startPrank(snlOwner1);

        bytes memory pools = generateStakingPools(stakingPools2, quantities1);

        /* Invalid staking pools */
        vm.expectRevert(bytes("39"));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_Paused() external {
        /* Pause yield adapter */
        vm.prank(users.deployer);
        XaiYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(snlOwner1);

        bytes memory pools = generateStakingPools(stakingPools1, quantities1);

        /* Claim when paused */
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        vm.startPrank(snlOwner1);

        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        bytes memory pools = generateStakingPools(stakingPools1, quantities1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_Unstaking() external {
        vm.startPrank(snlOwner2);

        bytes memory pools = generateStakingPools(stakingPools2, quantities2);

        /* Invalid staking pools */
        vm.expectRevert(bytes("39"));
        yieldPass.mint(yp, snlOwner2, snlOwner2, snlOwner2, block.timestamp, tokenIds3, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_WithoutKyc() external {
        /* Remove KYC */
        removeKyc(snlOwner1);

        /* Mint yield pass */
        vm.startPrank(snlOwner1);
        bytes memory pools = generateStakingPools(stakingPools1, quantities1);
        vm.expectRevert(abi.encodeWithSelector(XaiYieldAdapter.NotKycApproved.selector));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(snlOwner1);

        /* Mint at expiry */
        vm.warp(expiry);
        bytes memory pools = generateStakingPools(stakingPools1, quantities1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        /* Mint before start time */
        vm.warp(startTime - 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        vm.stopPrank();
    }
}
