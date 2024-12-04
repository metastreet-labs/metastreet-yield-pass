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
    uint256[] internal tokenIds1;
    uint256[] internal tokenIds2;
    uint256[] internal tokenIds3;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        (yp, dp) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds1 = new uint256[](1);
        tokenIds1[0] = 91521;

        tokenIds2 = new uint256[](1);
        tokenIds2[0] = 91522;

        tokenIds3 = new uint256[](2);
        tokenIds3[0] = 91523;
        tokenIds3[1] = 91524;
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds1,
            cnlOwner,
            cnlOwner,
            generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry),
            ""
        );
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
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds2,
            cnlOwner,
            cnlOwner,
            generateSignedNodess(operator, tokenIds2, halfWayPoint, 1, expiry),
            ""
        );
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

        /* Mint again with 2 token IDs */
        vm.startPrank(cnlOwner);
        yieldPass.mint(
            yp,
            cnlOwner,
            tokenIds3,
            cnlOwner,
            cnlOwner,
            generateSignedNodess(operator, tokenIds3, oneSecondBeforeExpiry, 1, expiry),
            ""
        );
        vm.stopPrank();

        uint256 expectedAmount3 = ((1 ether * (expiry - block.timestamp)) * 2) / (expiry - startTime);
        assertEq(
            IERC20(yp).balanceOf(cnlOwner),
            expectedAmount1 + expectedAmount2 + expectedAmount3,
            "Invalid yield token balance"
        );
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2 + expectedAmount3, "Invalid total supply");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91523), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91524), address(yieldAdapter), "Invalid NFT owner");
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

    function test__Mint_WithSmartWallet() external {
        vm.startPrank(cnlOwner);
        /* Transfer NFT to alt CNL owner */
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, 91521);
        vm.stopPrank();

        vm.startPrank(altCnlOwner);
        /* Generate transfer signature */
        bytes memory transferSignature = generateTransferSignature(address(smartAccount), tokenIds1);

        /* Mint through smart account */
        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature(
                "mint(address,address,uint256[],address,address,bytes,bytes)",
                yp,
                altCnlOwner,
                tokenIds1,
                address(smartAccount),
                address(smartAccount),
                generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry),
                transferSignature
            )
        );

        vm.stopPrank();

        uint256 expectedAmount = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(address(smartAccount)), expectedAmount, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount, "Invalid total supply");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(dp).ownerOf(91521), address(smartAccount), "Invalid discount token owner");
    }

    function test__Mint_WithSmartWallet_RevertWhen_InvalidTransferSignature() external {
        vm.startPrank(cnlOwner);
        /* Transfer NFT to alt CNL owner */
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, 91521);
        vm.stopPrank();

        vm.startPrank(altCnlOwner);
        bytes memory setupData = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry);

        /* Generate invalid transfer signature with invalid approved account */
        bytes memory transferSignature1 = generateTransferSignature(altCnlOwner, tokenIds1);

        /* Mint through smart account */
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidSignature.selector));
        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature(
                "mint(address,address,uint256[],address,address,bytes,bytes)",
                yp,
                altCnlOwner,
                tokenIds1,
                address(smartAccount),
                address(smartAccount),
                setupData,
                transferSignature1
            )
        );

        /* Generate invalid transfer signature with invalid token IDs */
        bytes memory transferSignature2 = generateTransferSignature(cnlOwner, tokenIds2);

        /* Mint through smart account */
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidSignature.selector));
        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature(
                "mint(address,address,uint256[],address,address,bytes,bytes)",
                yp,
                altCnlOwner,
                tokenIds1,
                address(smartAccount),
                address(smartAccount),
                setupData,
                transferSignature2
            )
        );

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_Paused() external {
        /* Pause yield adapter */
        vm.prank(users.deployer);
        AethirYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(cnlOwner);

        /* Mint when paused */
        bytes memory setupData = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData, "");
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        vm.startPrank(cnlOwner);

        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        bytes memory setupData = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(cnlOwner);

        /* Mint at expiry */
        vm.warp(expiry);
        bytes memory setupData1 = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData1, "");

        /* Mint before start time */
        vm.warp(startTime - 1);
        bytes memory setupData2 = generateSignedNodess(operator, tokenIds1, uint64(startTime - 1), 1, expiry);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData2, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidNodeTimestamp() external {
        vm.startPrank(cnlOwner);

        /* Mint with timestamp in the future */
        bytes memory setupData1 = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp + 1), 0, expiry);
        vm.expectRevert(abi.encodeWithSelector(AethirYieldAdapter.InvalidTimestamp.selector));
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData1, "");

        /* Mint with expired timestamp */
        bytes memory setupData2 = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp - 2), 1, expiry);
        vm.expectRevert(abi.encodeWithSelector(AethirYieldAdapter.InvalidTimestamp.selector));
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData2, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidExpiry() external {
        vm.startPrank(cnlOwner);

        bytes memory setupData = generateSignedNodess(operator, tokenIds1, uint64(block.timestamp), 1, expiry - 1);
        vm.expectRevert(abi.encodeWithSelector(AethirYieldAdapter.InvalidExpiry.selector));
        yieldPass.mint(yp, cnlOwner, tokenIds1, cnlOwner, cnlOwner, setupData, "");

        vm.stopPrank();
    }
}
