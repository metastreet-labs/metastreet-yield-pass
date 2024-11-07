// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirSepoliaBaseTest} from "./BaseSepolia.t.sol";
import {BaseTest} from "../pool/Base.t.sol";
import {PoolBaseTest} from "../pool/Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldPassUtils} from "src/interfaces/IYieldPassUtils.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import {AethirYieldAdapter} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import {Helpers} from "../pool/Helpers.sol";

import "forge-std/console.sol";

contract LiquidateTest is AethirSepoliaBaseTest {
    address internal yp;
    address internal dp;
    uint128 internal tick;
    address internal pair;

    function setUp() public override {
        /* Set up Nft */
        AethirSepoliaBaseTest.setUp();

        (yp, dp) =
            AethirSepoliaBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        PoolBaseTest.setMetaStreetPoolFactoryAndImpl(address(metaStreetPoolFactory), metaStreetPoolImpl);
        PoolBaseTest.deployMetaStreetPool(address(dp), address(ath), address(0));
        BaseTest.deployYieldPassUtils(address(uniswapV2Router), bundleCollateralWrapper);
        AethirSepoliaBaseTest.addWhitelist();

        setUpUniswap();
        setUpMSPool();
    }

    function setUpUniswap() internal {
        /* Transfer some ATH to CNL owner */
        vm.startPrank(athOwner);
        ath.transfer(cnlOwner, 100 ether);
        vm.stopPrank();

        vm.startPrank(cnlOwner);

        /* Mint to get some yield pass tokens */
        yieldPass.mint(
            yp, 776, cnlOwner, cnlOwner, generateSignedNode(operator, 776, uint64(block.timestamp), 1, expiry)
        );
        yieldPass.mint(
            yp, 777, cnlOwner, cnlOwner, generateSignedNode(operator, 777, uint64(block.timestamp), 1, expiry)
        );
        yieldPass.mint(
            yp, 778, cnlOwner, cnlOwner, generateSignedNode(operator, 778, uint64(block.timestamp), 1, expiry)
        );

        /* Create uniswap V2 pair */
        pair = uniswapV2Factory.createPair(address(yp), address(ath));

        /* Approve uniswap router */
        IERC20(yp).approve(address(uniswapV2Router), type(uint256).max);
        IERC20(ath).approve(address(uniswapV2Router), type(uint256).max);

        /* Add liquidity */
        uniswapV2Router.addLiquidity(
            address(yp), address(ath), 3 ether, 3 ether, 0, 0, address(cnlOwner), block.timestamp
        );

        vm.stopPrank();
    }

    function setUpMSPool() internal {
        /* Transfer some ATH to CNL owner */
        vm.startPrank(athOwner);

        /* Approve MS pool */
        IERC20(ath).approve(address(metaStreetPool), type(uint256).max);

        /* Get tick */
        tick = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Add deposit */
        metaStreetPool.deposit(tick, 100 ether, 0);
        vm.stopPrank();
    }

    function test__Liquidate_SingleToken() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 779;
        bytes[] memory setupData = new bytes[](1);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (, uint256 principal) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 1);

        /* Validate principal is not 0 */
        assertNotEq(principal, 0, "Principal is 0");

        /* Pool ATH balance */
        uint256 poolAthBalance = IERC20(ath).balanceOf(address(metaStreetPool));

        /* Liquidate */
        yieldPassUtils.liquidateToken(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            metaStreetPool.durations()[0],
            principal,
            ticks,
            "",
            principal,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        /* Check that pool ATH balance*/
        assertEq(IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance - principal, "Pool ATH balance wrong");

        /* Check Uniswap liquidity tokens balances */
        assertGt(IERC20(pair).balanceOf(cnlOwner), 0, "Liquidator has no liquidity tokens");
        assertEq(IERC20(pair).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils has no liquidity tokens");

        /* Check that yield pass token and ATH balances are 0 */
        assertEq(IERC20(yp).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has yield pass tokens");
        assertEq(IERC20(ath).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has ATH");
    }

    function test__Liquidate_MultipleTokens() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 779;
        tokenIds[1] = 780;
        bytes[] memory setupData = new bytes[](2);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        setupData[1] = generateSignedNode(operator, 780, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (, uint256 principal) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 2);

        /* Validate principal is not 0 */
        assertNotEq(principal, 0, "Principal is 0");

        /* Create encoded bundle */
        bytes memory encodedBundle = abi.encodePacked(dp);
        for (uint256 i; i < tokenIds.length; i++) {
            encodedBundle = abi.encodePacked(encodedBundle, tokenIds[i]);
        }

        /* Pool ATH balance */
        uint256 poolAthBalance = IERC20(ath).balanceOf(address(metaStreetPool));

        /* Liquidate */
        yieldPassUtils.liquidateToken(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            metaStreetPool.durations()[0],
            principal,
            ticks,
            abi.encodePacked(uint16(1), uint16(encodedBundle.length), encodedBundle),
            principal,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        /* Check that pool ATH balance*/
        assertEq(IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance - principal, "Pool ATH balance wrong");

        /* Check Uniswap liquidity tokens balances */
        assertGt(IERC20(pair).balanceOf(cnlOwner), 0, "Liquidator has no liquidity tokens");
        assertEq(IERC20(pair).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils has no liquidity tokens");

        /* Check that yield pass token and ATH balances are 0 */
        assertEq(IERC20(yp).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has yield pass tokens");
        assertEq(IERC20(ath).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has ATH");
    }

    function test__Liquidate_SingleToken_RevertWhen_DeadlinePassed() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 779;
        bytes[] memory setupData = new bytes[](1);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (, uint256 principal) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 1);

        /* Get durations */
        uint64 duration = metaStreetPool.durations()[0];

        /* Liquidate */
        vm.expectRevert(IYieldPassUtils.DeadlinePassed.selector);
        yieldPassUtils.liquidateToken(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            duration,
            principal,
            ticks,
            "",
            principal,
            uint64(block.timestamp - 1)
        );
        vm.stopPrank();
    }

    function test__Liquidate_SingleToken_RevertWhen_InvalidSlippage() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 779;
        bytes[] memory setupData = new bytes[](1);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (, uint256 principal) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 1);

        /* Get durations */
        uint64 duration = metaStreetPool.durations()[0];

        /* Liquidate */
        vm.expectRevert(IYieldPassUtils.InvalidSlippage.selector);
        yieldPassUtils.liquidateToken(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            duration,
            principal + 1,
            ticks,
            "",
            principal + 1,
            uint64(block.timestamp)
        );
        vm.stopPrank();
    }

    function test__LiquidatePartial_SingleToken() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 779;
        bytes[] memory setupData = new bytes[](1);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (uint256 yieldPassTokenAmount,) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 1);

        /* Pool ATH balance */
        uint256 poolAthBalance = IERC20(ath).balanceOf(address(metaStreetPool));

        /* Liquidator ATH balance */
        uint256 liquidatorAthBalance = IERC20(ath).balanceOf(cnlOwner);

        /* Liquidate */
        uint256 borrowAmount = 1 ether;
        yieldPassUtils.liquidateTokenPartial(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            borrowAmount,
            metaStreetPool.durations()[0],
            borrowAmount,
            ticks,
            "",
            uint64(block.timestamp)
        );
        vm.stopPrank();

        /* Check that pool ATH balance*/
        assertEq(
            IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance - borrowAmount, "Pool ATH balance wrong"
        );

        /* Check that liquidator yield pass token and ATH balances are correct */
        assertEq(IERC20(ath).balanceOf(cnlOwner), liquidatorAthBalance + borrowAmount, "Liquidator ATH balance wrong");
        assertEq(IERC20(yp).balanceOf(cnlOwner), yieldPassTokenAmount, "Liquidator yield pass token balance wrong");

        /* Check that yield pass token and ATH balances are 0 */
        assertEq(IERC20(yp).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has yield pass tokens");
        assertEq(IERC20(ath).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has ATH");
    }

    function test__LiquidatePartial_MultipleTokens() external {
        /* Mint */
        vm.startPrank(cnlOwner);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 779;
        tokenIds[1] = 780;
        bytes[] memory setupData = new bytes[](2);
        setupData[0] = generateSignedNode(operator, 779, uint64(block.timestamp), 1, expiry);
        setupData[1] = generateSignedNode(operator, 780, uint64(block.timestamp), 1, expiry);
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Quote principal */
        (uint256 yieldPassTokenAmount,) = yieldPassUtils.quoteLiquidateToken(address(yp), address(metaStreetPool), 2);

        /* Pool ATH balance */
        uint256 poolAthBalance = IERC20(ath).balanceOf(address(metaStreetPool));

        /* Liquidator ATH balance */
        uint256 liquidatorAthBalance = IERC20(ath).balanceOf(cnlOwner);

        /* Create encoded bundle */
        bytes memory encodedBundle = abi.encodePacked(dp);
        for (uint256 i; i < tokenIds.length; i++) {
            encodedBundle = abi.encodePacked(encodedBundle, tokenIds[i]);
        }

        /* Liquidate */
        uint256 borrowAmount = 1 ether;
        yieldPassUtils.liquidateTokenPartial(
            address(yp),
            tokenIds,
            setupData,
            address(metaStreetPool),
            borrowAmount,
            metaStreetPool.durations()[0],
            borrowAmount,
            ticks,
            abi.encodePacked(uint16(1), uint16(encodedBundle.length), encodedBundle),
            uint64(block.timestamp)
        );
        vm.stopPrank();

        /* Check that pool ATH balance*/
        assertEq(
            IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance - borrowAmount, "Pool ATH balance wrong"
        );

        /* Check that liquidator yield pass token and ATH balances are correct */
        assertEq(IERC20(ath).balanceOf(cnlOwner), liquidatorAthBalance + borrowAmount, "Liquidator ATH balance wrong");
        assertEq(IERC20(yp).balanceOf(cnlOwner), yieldPassTokenAmount, "Liquidator yield pass token balance wrong");

        /* Check that yield pass token and ATH balances are 0 */
        assertEq(IERC20(yp).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has yield pass tokens");
        assertEq(IERC20(ath).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils still has ATH");
    }
}
