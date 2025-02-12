// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TestYieldAdapterBaseTest} from "./Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

contract RedeemTest is TestYieldAdapterBaseTest {
    uint256[] internal tokenIds1;

    function setUp() public override {
        /* Set up */
        TestYieldAdapterBaseTest.setUp();

        tokenIds1 = new uint256[](2);
        tokenIds1[0] = 0;
        tokenIds1[1] = 1;

        /* Mint */
        vm.startPrank(users.normalUser1);
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");
        vm.stopPrank();
    }

    function test__Redeem() external {
        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Redeem */
        vm.startPrank(users.normalUser1);
        yieldPass.redeem(yp, users.normalUser1, tokenIds1);
        vm.stopPrank();

        /* Check that the node pass is burned */
        vm.expectRevert();
        IERC721(np).ownerOf(0);
        vm.expectRevert();
        IERC721(np).ownerOf(1);

        /* Check that yield adapter stil has nodes */
        assertEq(testNodeLicense.ownerOf(0), address(yieldAdapter), "Invalid node owner");
        assertEq(testNodeLicense.ownerOf(1), address(yieldAdapter), "Invalid node owner");
    }

    function test__Redeem_RevertWhen_TokenNotOwned() external {
        /* Transfer node pass away */
        vm.startPrank(users.normalUser1);
        IERC721(np).transferFrom(users.normalUser1, address(1), 1);
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Redeem */
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IYieldPass.InvalidRedemption.selector);
        yieldPass.redeem(yp, users.normalUser1, tokenIds1);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_InvalidWindow() external {
        /* Fast-forward to expiry */
        vm.warp(expiryTime);

        /* Redeem */
        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.redeem(yp, users.normalUser1, tokenIds1);
        vm.stopPrank();
    }
}
