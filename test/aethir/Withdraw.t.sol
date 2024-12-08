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
    address internal np;
    uint256[] internal tokenIds;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        (yp, np) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds = new uint256[](1);
        tokenIds[0] = 91521;
    }

    function test__Withdraw() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to 1 seconds after expiry */
        vm.warp(expiry + 1);

        /* Redeem */
        vm.startPrank(cnlOwner);
        yieldPass.redeem(yp, tokenIds);
        yieldPass.withdraw(yp, cnlOwner, tokenIds);
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), cnlOwner, "Invalid NFT owner");
    }

    function test__Withdraw_WithSmartWallet() external {
        vm.startPrank(cnlOwner);
        /* Transfer NFT to alt CNL owner */
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, 91521);
        vm.stopPrank();

        /* Mint */
        vm.startPrank(altCnlOwner);

        /* Generate transfer signature */
        uint256 deadline = block.timestamp + 1 days;
        bytes memory transferSignature = generateTransferSignature(address(smartAccount), deadline, tokenIds);

        /* Mint through smart account */
        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature(
                "mint(address,address,uint256[],address,address,uint256,bytes,bytes)",
                yp,
                altCnlOwner,
                tokenIds,
                address(smartAccount),
                address(smartAccount),
                deadline,
                generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
                transferSignature
            )
        );
        vm.stopPrank();

        /* Fast-forward to 1 seconds after expiry */
        vm.warp(expiry + 1);

        /* Redeem and withdraw */
        vm.startPrank(altCnlOwner);
        smartAccount.execute(address(yieldPass), 0, abi.encodeWithSignature("redeem(address,uint256[])", yp, tokenIds));
        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature("withdraw(address,address,uint256[])", yp, altCnlOwner, tokenIds)
        );
        vm.stopPrank();

        /* Validate that NFT is withdrawn */
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), altCnlOwner, "Invalid NFT owner");
    }

    function test__Withdraw_RevertWhen_InvalidWindow() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to expiry */
        vm.warp(expiry);

        /* Withdraw */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.withdraw(yp, cnlOwner, tokenIds);
        vm.stopPrank();
    }

    function test__Withdraw_RevertWhen_NotRedeemed() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
            ""
        );
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Withdraw */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidWithdrawal.selector);
        yieldPass.withdraw(yp, cnlOwner, tokenIds);
        vm.stopPrank();
    }
}
