// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./Base.t.sol";

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

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, np) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds1 = new uint256[](1);
        tokenIds1[0] = 19727;

        tokenIds2 = new uint256[](1);
        tokenIds2[0] = 19728;

        tokenIds3 = new uint256[](1);
        tokenIds3[0] = 19729;

        tokenIds4 = new uint256[](1);
        tokenIds4[0] = 22355;
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(
            yp, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, generateStakingPools(stakingPool), ""
        );
        vm.stopPrank();

        uint256 expectedAmount1 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(19727), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(19727), snlOwner, "Invalid node token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1, "Invalid claim state shares");

        /* Fast-forward to half-way point */
        vm.warp(startTime + ((expiry - startTime) / 2));

        /* Mint again */
        vm.startPrank(snlOwner);
        yieldPass.mint(
            yp, snlOwner, tokenIds2, snlOwner, snlOwner, block.timestamp, generateStakingPools(stakingPool), ""
        );
        vm.stopPrank();

        uint256 expectedAmount2 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner), expectedAmount1 + expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(19728), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(19728), snlOwner, "Invalid delegate token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1 + expectedAmount2, "Invalid claim state shares");
    }

    function test__Mint_RevertWhen_Paused() external {
        /* Pause yield adapter */
        vm.prank(users.deployer);
        XaiYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(snlOwner);

        bytes memory pools = generateStakingPools(stakingPool);

        /* Claim when paused */
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        vm.startPrank(snlOwner);

        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        bytes memory pools = generateStakingPools(stakingPool);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, pools, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_KeyIsStaked() external {
        vm.startPrank(snlOwner);

        bytes memory pools = generateStakingPools(stakingPool);

        /* Mint with staked key */
        vm.expectRevert();
        yieldPass.mint(yp, snlOwner, tokenIds4, snlOwner, snlOwner, block.timestamp, pools, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_WithoutKyc() external {
        /* Remove KYC */
        removeKyc(snlOwner);

        /* Mint yield pass */
        vm.startPrank(snlOwner);
        bytes memory pools = generateStakingPools(stakingPool);
        vm.expectRevert(abi.encodeWithSelector(XaiYieldAdapter.NotKycApproved.selector));
        yieldPass.mint(yp, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(snlOwner);

        /* Mint at expiry */
        vm.warp(expiry);
        bytes memory pools = generateStakingPools(stakingPool);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, pools, "");

        /* Mint before start time */
        vm.warp(startTime - 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner, tokenIds1, snlOwner, snlOwner, block.timestamp, pools, "");

        vm.stopPrank();
    }
}
