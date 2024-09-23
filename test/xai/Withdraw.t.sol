// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {XaiBaseTest} from "./Base.t.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract WithdrawTest is XaiBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, dp) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function test__Withdraw() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Fast-forward to 7 days before expiry */
        vm.warp(expiry - 7 days + 1);

        /* Redeem */
        vm.startPrank(snlOwner);
        yieldPass.redeem(yp, 19727);
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Withdraw */
        vm.startPrank(snlOwner);
        yieldPass.withdraw(yp, 19727, "", "");
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(sentryNodeLicense.ownerOf(19727), snlOwner, "Invalid NFT owner");
    }

    function test__Withdraw_RevertWhen_InvalidWindow() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Fast-forward to expiry */
        vm.warp(expiry);

        /* Withdraw */
        vm.startPrank(snlOwner);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.withdraw(yp, 19727, "", "");
        vm.stopPrank();
    }

    function test__Withdraw_RevertWhen_NotRedeemed() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Withdraw */
        vm.startPrank(snlOwner);
        vm.expectRevert(IYieldPass.InvalidWithdrawal.selector);
        yieldPass.withdraw(yp, 19727, "", "");
        vm.stopPrank();
    }
}
