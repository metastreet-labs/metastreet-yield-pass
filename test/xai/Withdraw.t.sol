// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {XaiBaseTest} from "./BaseArbSepolia.t.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

import "forge-std/console.sol";

contract WithdrawTest is XaiBaseTest {
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

    function test__Withdraw() external {
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

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(snlOwner1);
        yieldPass.redeem(yp, tokenIds);
        vm.stopPrank();

        /* Withdraw */
        vm.startPrank(snlOwner1);
        yieldPass.withdraw(yp, snlOwner1, tokenIds);
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(sentryNodeLicense.ownerOf(123714), snlOwner1, "Invalid NFT owner");
    }

    function test__Withdraw_RevertWhen_NotRedeemed() external {
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

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Withdraw */
        vm.startPrank(snlOwner1);
        vm.expectRevert(IYieldPass.InvalidWithdrawal.selector);
        yieldPass.withdraw(yp, snlOwner1, tokenIds);
        vm.stopPrank();
    }
}
