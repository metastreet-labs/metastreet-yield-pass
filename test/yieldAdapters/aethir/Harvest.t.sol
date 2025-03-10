// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {AethirYieldAdapter} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract HarvestTest is AethirBaseTest {
    address internal yp;
    address internal np;
    uint48 internal expiryTimestamp;
    uint256[] internal tokenIds;

    function setUp() public override {
        /* Set up Nft */
        AethirBaseTest.setUp();

        /* Mock set up */
        deployMockCheckerClaimAndWithdraw();
        deployYieldAdapter(true, false);
        addWhitelist();

        vm.prank(cnlOwner);
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldAdapter), true);

        (yp, np) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        expiryTimestamp = uint48(block.timestamp) + 360 days;

        tokenIds = new uint256[](1);
        tokenIds[0] = 91521;
    }

    function simulateYieldDistributionToCheckerClaimAndWithdraw() internal {
        uint256 beforeBalance = ath.balanceOf(mockCheckerClaimAndWithdraw);

        vm.startPrank(athOwner);
        ath.transfer(mockCheckerClaimAndWithdraw, 10_000_000);
        vm.stopPrank();

        uint256 afterBalance = ath.balanceOf(mockCheckerClaimAndWithdraw);
        assertEq(afterBalance, beforeBalance + 10_000_000, "Invalid balance");
    }

    function test__Harvest() external {
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

        /* Simulate yield distribution in checker claim and withdraw contract */
        simulateYieldDistributionToCheckerClaimAndWithdraw();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Generate claim data */
        bytes memory harvestData = generateHarvestData(true, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, harvestData);
        assertEq(amount, 0, "Invalid yield amount");
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 1_000_000, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 1_000_000, "Invalid cumulative yield");

        /* Validate state */
        assertEq(yieldPass.claimableYield(yp), 0, "Invalid claimable yield");
        assertEq(IERC20(ath).balanceOf(address(yieldAdapter)), 0, "Invalid ath balance");
        assertEq(yieldPass.yieldPassShares(yp), 1 ether, "Invalid total shares state");

        /* Fast-forward to after cliff */
        vm.warp(block.timestamp + 180 days);

        /* Generate withdraw data */
        harvestData = generateHarvestData(false, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        amount = yieldPass.harvest(yp, harvestData);
        assertEq(amount, 1_000_000, "Invalid yield amount");
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 1_000_000, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 1_000_000, "Invalid cumulative yield");

        /* Validate state */
        assertEq(yieldPass.claimableYield(yp), 1_000_000, "Invalid claimable yield");
        assertEq(IERC20(ath).balanceOf(address(yieldAdapter)), 1_000_000, "Invalid ath balance");
        assertEq(yieldPass.yieldPassShares(yp), 1 ether, "Invalid total shares state");
    }

    function test__Harvest_RevertWhen_HarvestCompleted() external {
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

        /* Simulate yield distribution in checker claim and withdraw contract */
        simulateYieldDistributionToCheckerClaimAndWithdraw();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Generate claim data */
        bytes memory harvestData = generateHarvestData(true, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        yieldPass.harvest(yp, harvestData);
        vm.stopPrank();

        /* Generate claim data */
        harvestData = generateHarvestData(true, expiryTimestamp, false);

        /* Fast-forward to 10 seconds after expiry */
        vm.warp(expiry + 10);

        /* Expect revert */
        vm.expectRevert(abi.encodeWithSelector(IYieldAdapter.HarvestCompleted.selector));
        yieldPass.harvest(yp, harvestData);
        vm.stopPrank();
    }

    function test__Harvest_RevertWhen_InvalidCliffSeconds() external {
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

        /* Simulate yield distribution in checker claim and withdraw contract */
        simulateYieldDistributionToCheckerClaimAndWithdraw();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Generate claim data */
        bytes memory harvestData = generateHarvestData(true, expiryTimestamp, true);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        vm.expectRevert(AethirYieldAdapter.InvalidCliff.selector);
        yieldPass.harvest(yp, harvestData);
        vm.stopPrank();
    }

    function test__Harvest_RevertWhen_UndeployedYieldPass() external {
        /* Undeployed yield pass */
        address randomAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

        /* Harvest yield */
        vm.startPrank(users.deployer);

        vm.expectRevert(abi.encodeWithSelector(IYieldPass.InvalidYieldPass.selector));
        yieldPass.harvest(randomAddress, "");
        vm.stopPrank();
    }
}
