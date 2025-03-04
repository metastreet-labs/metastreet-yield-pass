// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {SophonBaseTest, IGuardianDelegation} from "./BaseSophon.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {NodePassToken} from "src/NodePassToken.sol";
import {SophonYieldAdapter} from "src/yieldAdapters/sophon/SophonYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract SophonMintTest is SophonBaseTest {
    address internal yp;
    address internal np;
    uint256[] internal tokenIds1;
    uint256[] internal tokenIds2;
    uint256[] internal tokenIds3;
    uint256[] internal tokenIds4;
    address[] internal stakingPools1;
    uint256[] internal quantities1;
    uint256[] internal quantities2;

    function setUp() public override {
        /* Set up Nft */
        SophonBaseTest.setUp();

        (yp, np) = SophonBaseTest.deployYieldPass(address(sophonNodeLicense), startTime, expiry, address(yieldAdapter));

        /* Sentry node license owner of 13416, 13417, 13418, 13419, 13420, 13421 */
        tokenIds1 = new uint256[](1);
        tokenIds1[0] = 13416;

        tokenIds2 = new uint256[](2);
        tokenIds2[0] = 13417;
        tokenIds2[1] = 13418;

        tokenIds3 = new uint256[](2);
        tokenIds3[0] = 13419;
        tokenIds3[1] = 13420;

        tokenIds4 = new uint256[](1);
        tokenIds4[0] = 13421;

        stakingPools1 = new address[](1);
        stakingPools1[0] = stakingPool1;

        quantities1 = new uint256[](1);
        quantities1[0] = 1;

        quantities2 = new uint256[](1);
        quantities2[0] = 2;
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds1,
            generateStakingLightNodes(stakingPools1, quantities1),
            ""
        );
        vm.stopPrank();

        uint256 expectedAmount1 = (1 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner1), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(sophonNodeLicense.ownerOf(13416), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(13416), snlOwner1, "Invalid node token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.yieldPassShares(yp), expectedAmount1, "Invalid claim state shares");
        assertEq(guardianDelegationProxy.balanceOfSent(address(yieldAdapter)), 1, "Invalid count received");

        /* Fast-forward to half-way point */
        vm.warp(startTime + ((expiry - startTime) / 2));

        /* Mint again */
        vm.startPrank(snlOwner1);
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds2,
            generateStakingLightNodes(stakingPools1, quantities2),
            ""
        );
        vm.stopPrank();

        uint256 expectedAmount2 = (2 ether * (expiry - block.timestamp)) / (expiry - startTime);
        assertEq(IERC20(yp).balanceOf(snlOwner1), expectedAmount1 + expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");
        assertEq(sophonNodeLicense.ownerOf(13417), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(13417), snlOwner1, "Invalid delegate token owner");
        assertEq(sophonNodeLicense.ownerOf(13418), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(13418), snlOwner1, "Invalid delegate token owner");

        assertEq(yieldPass.cumulativeYield(yp, 0), 0, "Invalid cumulative yield");
        assertEq(yieldPass.yieldPassShares(yp), expectedAmount1 + expectedAmount2, "Invalid claim state shares");

        assertEq(guardianDelegationProxy.balanceOfSent(address(yieldAdapter)), 3, "Invalid count received");
    }

    function test__Mint_RevertWhen_Paused() external {
        /* Pause yield adapter */
        vm.prank(users.deployer);
        SophonYieldAdapter(address(yieldAdapter)).pause();

        vm.startPrank(snlOwner1);

        bytes memory pools = generateStakingLightNodes(stakingPools1, quantities1);

        /* Claim when paused */
        vm.expectRevert(Pausable.EnforcedPause.selector);
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");
        vm.stopPrank();
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        vm.startPrank(snlOwner1);

        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        bytes memory pools = generateStakingLightNodes(stakingPools1, quantities1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(snlOwner1);

        /* Mint at expiry */
        vm.warp(expiry);
        bytes memory pools = generateStakingLightNodes(stakingPools1, quantities1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        /* Mint before start time */
        vm.warp(startTime - 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, snlOwner1, snlOwner1, snlOwner1, block.timestamp, tokenIds1, pools, "");

        vm.stopPrank();
    }
}
