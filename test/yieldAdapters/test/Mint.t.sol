// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {TestYieldAdapterBaseTest} from "./Base.t.sol";

import {YieldPassToken} from "src/YieldPassToken.sol";
import {NodePassToken} from "src/NodePassToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";

contract TestYieldAdapterMintTest is TestYieldAdapterBaseTest {
    uint256[] internal tokenIds1;
    uint256[] internal tokenIds2;

    function setUp() public override {
        /* Set up */
        TestYieldAdapterBaseTest.setUp();

        tokenIds1 = new uint256[](2);
        tokenIds1[0] = 0;
        tokenIds1[1] = 1;

        tokenIds2 = new uint256[](3);
        tokenIds2[0] = 2;
        tokenIds2[1] = 3;
        tokenIds2[2] = 4;
    }

    function test__TokenGetters() external view {
        assertEq(YieldPassToken(yp).yieldPassFactory(), address(yieldPass), "Invalid yield pass factory");
        assertEq(NodePassToken(np).yieldPassFactory(), address(yieldPass), "Invalid yield pass factory");

        assertEq(NodePassToken(np).yieldPass(), yp, "Invalid yield pass token");
    }

    function test__Mint() external {
        /* Mint */
        vm.startPrank(users.normalUser1);
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");
        vm.stopPrank();

        uint256 expectedAmount1 = (2 ether * (expiryTime - block.timestamp)) / (expiryTime - startTime);
        assertEq(IERC20(yp).balanceOf(users.normalUser1), expectedAmount1, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1, "Invalid total supply");
        assertEq(testNodeLicense.ownerOf(0), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(0), users.normalUser1, "Invalid node pass owner");
        assertEq(testNodeLicense.ownerOf(1), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(1), users.normalUser1, "Invalid node pass owner");

        assertEq(yieldPass.cumulativeYield(yp), 0, "Invalid cumulative yield");
        assertEq(yieldPass.yieldPassShares(yp), expectedAmount1, "Invalid claim state shares");

        /* Fast-forward to half-way point */
        vm.warp(startTime + ((expiryTime - startTime) / 2));

        /* Mint again */
        vm.startPrank(users.normalUser2);
        yieldPass.mint(yp, users.normalUser2, users.normalUser2, block.timestamp, tokenIds2, "");
        vm.stopPrank();

        uint256 expectedAmount2 = (3 ether * (expiryTime - block.timestamp)) / (expiryTime - startTime);
        assertEq(IERC20(yp).balanceOf(users.normalUser2), expectedAmount2, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), expectedAmount1 + expectedAmount2, "Invalid total supply");

        assertEq(testNodeLicense.ownerOf(2), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(2), users.normalUser2, "Invalid node pass owner");
        assertEq(testNodeLicense.ownerOf(3), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(3), users.normalUser2, "Invalid node pass owner");
        assertEq(testNodeLicense.ownerOf(4), address(yieldAdapter), "Invalid node owner");
        assertEq(IERC721(np).ownerOf(4), users.normalUser2, "Invalid node pass owner");

        assertEq(yieldPass.cumulativeYield(yp), 0, "Invalid cumulative yield");
        assertEq(yieldPass.yieldPassShares(yp), expectedAmount1 + expectedAmount2, "Invalid claim state shares");
    }

    function test__Mint_RevertWhen_UndeployedYieldPass() external {
        vm.startPrank(users.normalUser1);

        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.mint(randomAddress, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");

        vm.stopPrank();
    }

    function test__Mint_RevertWhen_InvalidMintWindow() external {
        vm.startPrank(users.normalUser1);

        /* Mint at expiry */
        vm.warp(expiryTime);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");

        /* Mint before start time */
        vm.warp(startTime - 1);
        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidWindow.selector));
        yieldPass.mint(yp, users.normalUser1, users.normalUser1, block.timestamp, tokenIds1, "");

        vm.stopPrank();
    }
}
