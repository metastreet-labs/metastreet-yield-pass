// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {XaiBaseTest} from "./Base.t.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract RedeemTest is XaiBaseTest {
    address internal yp;
    address internal dp;

    function setUp() public override {
        /* Set up Nft */
        XaiBaseTest.setUp();

        (yp, dp) = XaiBaseTest.deployYieldPass(address(sentryNodeLicense), startTime, expiry, address(yieldAdapter));
    }

    function test__Redeem() external {
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

        /* Check that the discount pass is burned */
        vm.expectRevert();
        IERC721(dp).ownerOf(19727);
    }

    function test__Redeem_RevertWhen_TokenNotOwned() external {
        /* Turn on transferability */
        vm.startPrank(users.deployer);
        yieldPass.setTransferable(yp, true);
        vm.stopPrank();

        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        IERC721(dp).transferFrom(snlOwner, address(1), 19727);
        vm.stopPrank();

        /* Fast-forward to 7 days before expiry */
        vm.warp(expiry - 7 days + 1);

        /* Redeem */
        vm.startPrank(snlOwner);
        vm.expectRevert(IYieldPass.InvalidRedemption.selector);
        yieldPass.redeem(yp, 19727);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_InvalidWindow() external {
        /* Mint */
        vm.startPrank(snlOwner);
        yieldPass.mint(yp, 19727, snlOwner, snlOwner, abi.encode(stakingPool));
        vm.stopPrank();

        /* Fast-forward to 1 seconds before 7 days before expiry */
        vm.warp(expiry - 7 days - 1);

        /* Redeem */
        vm.startPrank(snlOwner);
        vm.expectRevert(abi.encodeWithSelector(XaiYieldAdapter.InvalidWindow.selector));
        yieldPass.redeem(yp, 19727);
        vm.stopPrank();
    }
}
