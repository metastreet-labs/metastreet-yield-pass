// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TestYieldAdapterBaseTest} from "./Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

contract WithdrawTest is TestYieldAdapterBaseTest {
    uint256[] internal tokenIds1;

    function setUp() public override {
        /* Set up */
        TestYieldAdapterBaseTest.setUp();

        tokenIds1 = new uint256[](2);
        tokenIds1[0] = 0;
        tokenIds1[1] = 1;

        /* Mint */
        vm.startPrank(users.normalUser1);
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "", "");
        vm.stopPrank();
    }

    function test__Withdraw() external {
        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Redeem */
        vm.startPrank(users.normalUser1);
        yieldPass.redeem(yp, users.normalUser1, tokenIds1);
        vm.stopPrank();

        /* Withdraw */
        vm.startPrank(users.normalUser1);
        yieldPass.withdraw(yp, tokenIds1);
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(testNodeLicense.ownerOf(0), users.normalUser1, "Invalid node owner");
        assertEq(testNodeLicense.ownerOf(1), users.normalUser1, "Invalid node owner");
    }

    function test__Withdraw_RevertWhen_NotRedeemed() external {
        /* Fast-forward to after expiry */
        vm.warp(expiryTime + 1);

        /* Withdraw */
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IYieldPass.InvalidWithdrawal.selector);
        yieldPass.withdraw(yp, tokenIds1);
        vm.stopPrank();
    }
}
