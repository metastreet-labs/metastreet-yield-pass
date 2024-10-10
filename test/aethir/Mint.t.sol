// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import {AethirYieldAdapter, IERC4907} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import "forge-std/console.sol";

contract MintTest is AethirBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        (yp, dp) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, generateSignedNode(operator, 91521, uint64(block.timestamp), 1));
        vm.stopPrank();

        uint256 expectedAmount1 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(cnlOwner), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(91521), cnlOwner, "Invalid discount token owner");

        assertEq(yieldPass.cumulativeYield(yp), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1, "Invalid claim state shares");

        /* Fast-forward to half-way point */
        uint64 halfWayPoint = startTime + ((expiry - startTime) / 2);
        vm.warp(halfWayPoint);

        /* Mint again */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91522, cnlOwner, cnlOwner, generateSignedNode(operator, 91522, halfWayPoint, 1));
        vm.stopPrank();

        uint256 expectedAmount2 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(cnlOwner), expectedAmount1 + expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91522), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(91522), cnlOwner, "Invalid delegate token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.claimState(yp).total, 0, "Invalid claim state total");
        assertEq(yieldPass.claimState(yp).balance, 0, "Invalid claim state balance");
        assertEq(yieldPass.claimState(yp).shares, expectedAmount1 + expectedAmount2, "Invalid claim state shares");

        /* Fast-forward to 1 second before expiry */
        uint64 oneSecondBeforeExpiry = expiry - 1;
        vm.warp(oneSecondBeforeExpiry);

        /* Mint again */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91523, cnlOwner, cnlOwner, generateSignedNode(operator, 91523, oneSecondBeforeExpiry, 1));
        vm.stopPrank();

        uint256 expectedAmount3 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(
            IERC20(yp).balanceOf(cnlOwner),
            expectedAmount1 + expectedAmount2 + expectedAmount3,
            "Invalid yield token balance"
        );
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2 + expectedAmount3, "Invalid total supply");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91523), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(91523), cnlOwner, "Invalid delegate token owner");

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
        AethirYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(cnlOwner);

        /* Mint when paused */
        bytes memory setupData = generateSignedNode(operator, 91521, uint64(block.timestamp), 1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, setupData);
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

        bytes memory setupData = generateSignedNode(operator, 91521, uint64(block.timestamp), 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, 91521, cnlOwner, cnlOwner, setupData);
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        /* Mint at expiry */
        vm.warp(expiry);
        bytes memory setupData1 = generateSignedNode(operator, 91521, uint64(block.timestamp), 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, setupData1);

        /* Mint before start time */
        vm.warp(startTime - 1);
        bytes memory setupData2 = generateSignedNode(operator, 91521, uint64(startTime - 1), 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, setupData2);
    }

    function test__Mint_RevertWhen_InvalidNodeTimestamp() external {
        vm.startPrank(cnlOwner);

        /* Mint with timestamp in the future */
        bytes memory setupData1 = generateSignedNode(operator, 91521, uint64(block.timestamp + 1), 0);
        vm.expectRevert(abi.encodeWithSelector(AethirYieldAdapter.InvalidTimestamp.selector));
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, setupData1);

        /* Mint with expired timestamp */
        bytes memory setupData2 = generateSignedNode(operator, 91521, uint64(block.timestamp - 2), 1);
        vm.expectRevert(abi.encodeWithSelector(AethirYieldAdapter.InvalidTimestamp.selector));
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, setupData2);

        vm.stopPrank();
    }
}
