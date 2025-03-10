// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {AethirBaseTest} from "./Base.t.sol";

import {AethirYieldAdapter, IERC4907} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";
import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import {NodePassToken} from "src/NodePassToken.sol";

import "forge-std/console.sol";

contract RedeemTest is AethirBaseTest {
    address internal yp;
    address internal np;
    uint256[] internal tokenIds;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        (yp, np) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds = new uint256[](1);
        tokenIds[0] = 91521;
    }

    function test__Redeem() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            tokenIds,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to 1 seconds after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(cnlOwner);
        yieldPass.redeem(yp, cnlOwner, tokenIds);
        vm.stopPrank();

        /* Check that the node pass is burned */
        vm.expectRevert();
        IERC721(np).ownerOf(91521);
    }

    function test__Redeem_RevertWhen_TokenNotOwned() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            tokenIds,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        IERC721(np).transferFrom(cnlOwner, address(1), 91521);
        vm.stopPrank();

        /* Fast-forward to 1 seconds after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidRedemption.selector);
        yieldPass.redeem(yp, cnlOwner, tokenIds);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_InvalidWindow() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            tokenIds,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to expiry */
        vm.warp(expiry);

        /* Redeem */
        vm.startPrank(cnlOwner);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.redeem(yp, cnlOwner, tokenIds);
        vm.stopPrank();
    }

    function test__Redeem_RevertWhen_TransferLocked() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            tokenIds,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldAdapter.InvalidRecipient.selector);
        yieldPass.redeem(yp, altCnlOwner, tokenIds);
        vm.stopPrank();
    }
}
