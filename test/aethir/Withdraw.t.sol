// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {AethirBaseTest} from "./Base.t.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract WithdrawTest is AethirBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        (yp, dp) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function test__Withdraw() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, generateSignedNode(operator, 91521, uint64(block.timestamp), 1));
        vm.stopPrank();

        /* Fast-forward to 1 seconds after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(cnlOwner);
        yieldPass.redeem(yp, 91521);
        yieldPass.withdraw(yp, 91521, "", "");
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), cnlOwner, "Invalid NFT owner");
    }

    function test__Withdraw_RevertWhen_InvalidWindow() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, generateSignedNode(operator, 91521, uint64(block.timestamp), 1));
        vm.stopPrank();

        /* Fast-forward to expiry */
        vm.warp(expiry);

        /* Withdraw */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.withdraw(yp, 91521, "", "");
        vm.stopPrank();
    }

    function test__Withdraw_RevertWhen_NotRedeemed() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(yp, 91521, cnlOwner, cnlOwner, generateSignedNode(operator, 91521, uint64(block.timestamp), 1));
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Withdraw */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidWithdrawal.selector);
        yieldPass.withdraw(yp, 91521, "", "");
        vm.stopPrank();
    }
}
