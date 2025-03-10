// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

contract ClaimTest is AethirBaseTest {
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

        vm.prank(altCnlOwner);
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldAdapter), true);

        (yp, np) = AethirBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        expiryTimestamp = uint48(block.timestamp) + 360 days;

        tokenIds = new uint256[](1);
        tokenIds[0] = 91521;
    }

    function harvest() internal {
        /* Simulate yield distribution in checker claim and withdraw contract */
        simulateYieldDistributionToCheckerClaimAndWithdraw();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 1);

        /* Generate claim data */
        bytes memory harvestData = generateHarvestData(true, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        uint256 amount = yieldPass.harvest(yp, harvestData);
        vm.stopPrank();

        /* Fast-forward to after cliff */
        vm.warp(block.timestamp + 180 days);

        /* Generate withdraw data */
        harvestData = generateHarvestData(false, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        amount = yieldPass.harvest(yp, harvestData);
        vm.stopPrank();
    }

    function simulateYieldDistributionToCheckerClaimAndWithdraw() internal {
        uint256 beforeBalance = ath.balanceOf(mockCheckerClaimAndWithdraw);

        vm.startPrank(athOwner);
        ath.transfer(mockCheckerClaimAndWithdraw, 10_000_000);
        vm.stopPrank();

        uint256 afterBalance = ath.balanceOf(mockCheckerClaimAndWithdraw);
        assertEq(afterBalance, beforeBalance + 10_000_000, "Invalid balance");
    }

    function test__Claim() external {
        /* Get user initial ath balance */
        uint256 initialBalance = ath.balanceOf(cnlOwner);

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

        /* Harvest */
        harvest();

        /* Claim */
        vm.startPrank(cnlOwner);
        yieldPass.claim(yp, cnlOwner, IERC20(yp).balanceOf(cnlOwner));
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 1_000_000, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 1_000_000, "Invalid cumulative yield");

        /* Check claimable yield */
        assertEq(yieldPass.claimableYield(yp), 0, "Invalid claimable yield");
        assertEq(IERC20(yp).balanceOf(cnlOwner), 0, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), 0, "Invalid total supply");
        assertEq(IERC20(ath).balanceOf(cnlOwner), initialBalance + 1_000_000, "Invalid ath balance");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(91521), cnlOwner, "Invalid delegate token owner");
        assertEq(yieldPass.yieldPassShares(yp), 1 ether, "Invalid total shares state");
    }

    function test__Claim_WithSmartWallet() external {
        vm.startPrank(cnlOwner);
        /* Transfer NFT to alt CNL owner */
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, 91521);
        vm.stopPrank();

        /* Get user initial ath balance */
        uint256 initialBalance = ath.balanceOf(address(smartAccount));

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
                "mint(address,address,address,address,uint256,uint256[],bytes,bytes)",
                yp,
                altCnlOwner,
                address(smartAccount),
                address(smartAccount),
                deadline,
                tokenIds,
                generateSignedNodes(operator, tokenIds, uint64(block.timestamp), 1, expiry),
                transferSignature
            )
        );
        vm.stopPrank();

        /* Harvest */
        harvest();

        /* Claim */
        vm.startPrank(altCnlOwner);

        smartAccount.execute(
            address(yieldPass),
            0,
            abi.encodeWithSignature(
                "claim(address,address,uint256)", yp, address(smartAccount), IERC20(yp).balanceOf(address(smartAccount))
            )
        );
        vm.stopPrank();

        /* Check cumulative yield */
        assertEq(yieldPass.cumulativeYield(yp), 1_000_000, "Invalid cumulative yield");
        assertEq(yieldPass.cumulativeYield(yp, 1 ether), 1_000_000, "Invalid cumulative yield");

        /* Check claimable yield */
        assertEq(yieldPass.claimableYield(yp), 0, "Invalid claimable yield");
        assertEq(IERC20(yp).balanceOf(address(smartAccount)), 0, "Invalid yield token balance");
        assertEq(IERC20(yp).totalSupply(), 0, "Invalid total supply");
        assertEq(IERC20(ath).balanceOf(address(smartAccount)), initialBalance + 1_000_000, "Invalid ath balance");
        assertEq(IERC721(checkerNodeLicense).ownerOf(91521), address(yieldAdapter), "Invalid NFT owner");
        assertEq(IERC721(np).ownerOf(91521), address(smartAccount), "Invalid delegate token owner");
        assertEq(yieldPass.yieldPassShares(yp), 1 ether, "Invalid total shares state");
    }

    function test__Claim_RevertWhen_InvalidAmount() external {
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

        /* Harvest */
        harvest();

        vm.startPrank(cnlOwner);

        /* Claim with 0 */
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, cnlOwner, 0);

        /* Claim with insufficient balance amount */
        uint256 userBalance = IERC20(yp).balanceOf(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidAmount.selector);
        yieldPass.claim(yp, cnlOwner, userBalance + 1);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_InvalidClaimWindow() external {
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

        /* Claim early */
        vm.startPrank(cnlOwner);
        uint256 userBalance = IERC20(yp).balanceOf(cnlOwner);
        vm.expectRevert(IYieldPass.InvalidWindow.selector);
        yieldPass.claim(yp, cnlOwner, userBalance);
        vm.stopPrank();
    }

    function test__Claim_RevertWhen_HarvestNotCompleted() external {
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

        /* Fast-forward to before expiry */
        vm.warp(expiry - 1);

        /* Generate claim data */
        bytes memory harvestData = generateHarvestData(true, expiryTimestamp, false);

        /* Harvest yield */
        vm.startPrank(users.deployer);
        yieldPass.harvest(yp, harvestData);
        vm.stopPrank();

        /* Fast-forward to after expiry */
        vm.warp(expiry + 10);

        /* Try to claim before final harvest */
        vm.startPrank(cnlOwner);
        vm.expectRevert(IYieldAdapter.HarvestNotCompleted.selector);
        yieldPass.claim(yp, cnlOwner, 100);
        vm.stopPrank();
    }
}
