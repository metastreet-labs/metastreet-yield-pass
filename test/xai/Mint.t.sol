// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {XaiBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {DiscountPassToken} from "src/DiscountPassToken.sol";
import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract XaiMintTest is XaiBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, dp) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        uint256 expectedAmount1 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(19727), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(19727), snlOwner, "Invalid discount token owner");

        vm.expectRevert(DiscountPassToken.NotTransferable.selector);
        IERC721(dp).transferFrom(snlOwner, address(1), 19727);

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1, "Invalid claim state shares");

        /* Fast-forward to half-way point */
        vm.warp(startTime + ((expiry - startTime) / 2));

        /* Mint again */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19728, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        uint256 expectedAmount2 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner), expectedAmount1 + expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(19728), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(19728), snlOwner, "Invalid delegate token owner");

        vm.expectRevert(DiscountPassToken.NotTransferable.selector);
        IERC721(dp).transferFrom(snlOwner, address(1), 19728);

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1 + expectedAmount2, "Invalid claim state shares");

        /* Fast-forward to 1 second before expiry */
        vm.warp(expiry - 1);

        /* Mint again */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19729, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        uint256 expectedAmount3 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(
            IERC20(yp).balanceOf(snlOwner),
            expectedAmount1 + expectedAmount2 + expectedAmount3,
            "Invalid yield token balance"
        );
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2 + expectedAmount3, "Invalid total supply");
        assertEq(sentryNodeLicense.ownerOf(19729), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(19729), snlOwner, "Invalid delegate token owner");

        vm.expectRevert(DiscountPassToken.NotTransferable.selector);
        IERC721(dp).transferFrom(snlOwner, address(1), 19729);

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(
            yieldPass.claimState(yp).shares,
            expectedAmount1 + expectedAmount2 + expectedAmount3,
            "Invalid claim state shares"
        );
    }

    function test__Mint_RevertWhen_Paused() external {
        /* Pause yield adapter */
        vm.prank(users.deployer);
        XaiYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(snlOwner);

        /* Claim when paused */
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
    }

    function test__Mint_RevertWhen_KeyIsStaked() external {
        vm.startPrank(snlOwner);

        /* Mint with staked key */
        vm.expectRevert();
        yieldPass.mint(yp, 22355, snlOwner, snlOwner, abi.encode(stakingPool));

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_WithoutKyc() external {
        /* Remove KYC */
        removeKyc(snlOwner);

        /* Mint yield pass */
        vm.startPrank(snlOwner);
        vm.expectRevert(abi.encodeWithSelector(XaiYieldAdapter.NotKycApproved.selector));
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(snlOwner);

        /* Mint at expiry */
        vm.warp(expiry);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));

        /* Mint before start time */
        vm.warp(startTime - 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));

        vm.stopPrank();
    }
}
