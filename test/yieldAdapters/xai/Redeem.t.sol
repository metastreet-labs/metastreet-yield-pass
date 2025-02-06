// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {XaiBaseTest} from "./BaseArbSepolia.t.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract RedeemTest is XaiBaseTest {
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

    function test__Redeem() external {
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
        yieldPass.redeem(yp, snlOwner1, tokenIds);
        vm.stopPrank();

        /* Check that the node pass is burned */
        vm.expectRevert();
        IERC721(np).ownerOf(123714);
    }

    function test__Redeem_RevertWhen_TokenNotOwned() external {
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
        IERC721(np).transferFrom(snlOwner1, address(1), 123714);
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(snlOwner1);
        vm.expectRevert(IYieldPass.InvalidRedemption.selector);
        yieldPass.redeem(yp, snlOwner1, tokenIds);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_InvalidWindow() external {
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

        /* Fast-forward to expiry */
        vm.warp(expiry);

        /* Redeem */
        vm.startPrank(snlOwner1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.redeem(yp, snlOwner1, tokenIds);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_TransferLocked() external {
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
        vm.expectRevert(IYieldAdapter.InvalidRecipient.selector);
        yieldPass.redeem(yp, snlOwner2, tokenIds);
        vm.stopPrank();
    }
}
