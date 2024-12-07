// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirSepoliaBaseTest, ICoinbaseSmartWallet} from "./BaseSepolia.t.sol";
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

interface IBundleCollateralWrapper {
    function enumerateWithQuantities(
        uint256 tokenId,
        bytes calldata context
    ) external view returns (address token, uint256[] memory tokenIds, uint256[] memory quantities);
    function tokenCount(uint256 tokenId, bytes calldata context) external view returns (uint256);

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid context
     */
    error InvalidContext();

    /**
     * @notice Invalid bundle size
     */
    error InvalidSize();
}

contract LiquidateTest is AethirSepoliaBaseTest {
    address internal yp;
    address internal dp;
    uint128 internal tick;
    address internal pair;
    uint256[] internal tokenIds1;
    uint256[] internal tokenIds2;

    function setUp() public override {
        /* Set up Nft */
        AethirSepoliaBaseTest.setUp();

        (yp, dp) =
            AethirSepoliaBaseTest.deployYieldPass(address(checkerNodeLicense), startTime, expiry, address(yieldAdapter));

        tokenIds1 = new uint256[](3);
        tokenIds1[0] = 776;
        tokenIds1[1] = 777;
        tokenIds1[2] = 778;

        tokenIds2 = new uint256[](2);
        tokenIds2[0] = 779;
        tokenIds2[1] = 780;

        PoolBaseTest.setMetaStreetPoolFactoryAndImpl(address(metaStreetPoolFactory), metaStreetPoolImpl);
        PoolBaseTest.deployMetaStreetPool(address(dp), address(ath), address(0));
        BaseTest.deployYieldPassUtils(address(uniswapV2Factory));

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
            yp,
            cnlOwner,
            tokenIds1,
            cnlOwner,
            cnlOwner,
            block.timestamp,
            generateSignedNodes(operator, tokenIds1, uint64(block.timestamp), 1, expiry),
            ""
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

    function test__MintAndLP() external {
        vm.startPrank(cnlOwner);
        /* Transfer NFT to alt CNL owner */
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, tokenIds2[0]);
        IERC721(checkerNodeLicense).transferFrom(cnlOwner, altCnlOwner, tokenIds2[1]);
        vm.stopPrank();

        vm.startPrank(altCnlOwner);
        /* Generate setup data */
        bytes memory setupData = generateSignedNodes(operator, tokenIds2, uint64(block.timestamp), 1, expiry);

        /* Get ticks */
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Generate transfer signature */
        uint256 deadline = block.timestamp + 1 days;
        bytes memory transferSignature = generateTransferSignature(address(smartAccount), deadline, tokenIds2);

        /* Approve NFTs */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPassUtils), true);

        /* Pool ATH balance */
        uint256 poolAthBalance = IERC20(ath).balanceOf(address(metaStreetPool));

        /* Calls 1 */
        ICoinbaseSmartWallet.Call[] memory calls1 = new ICoinbaseSmartWallet.Call[](4);

        /* Mint 2 node licenses */
        calls1[0] = ICoinbaseSmartWallet.Call({
            target: address(yieldPass),
            value: 0,
            data: abi.encodeWithSignature(
                "mint(address,address,uint256[],address,address,uint256,bytes,bytes)",
                yp,
                altCnlOwner,
                tokenIds2,
                address(smartAccount),
                address(smartAccount),
                deadline,
                setupData,
                transferSignature
            )
        });

        /* Set approval for DPs for bundle collateral wrapper */
        calls1[1] = ICoinbaseSmartWallet.Call({
            target: dp,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", bundleCollateralWrapper, true)
        });

        /* Bundle DPs */
        calls1[2] = ICoinbaseSmartWallet.Call({
            target: bundleCollateralWrapper,
            value: 0,
            data: abi.encodeWithSignature("mint(address,uint256[])", dp, tokenIds2)
        });

        /* Unset approval for bundle collateral wrapper for DP */
        calls1[3] = ICoinbaseSmartWallet.Call({
            target: dp,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", bundleCollateralWrapper, false)
        });

        vm.recordLogs();

        /* Execute mint and bundle */
        smartAccount.executeBatch(calls1);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 bundleTokenId;
        bytes memory encodedBundle;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("BundleMinted(uint256,address,bytes)")) {
                bundleTokenId = uint256(entries[i].topics[1]);
                encodedBundle = abi.decode(entries[i].data, (bytes));

                /* Validate smart account has bundle collateral wrapper token */
                assertEq(
                    IERC721(bundleCollateralWrapper).ownerOf(bundleTokenId), address(smartAccount), "Invalid NFT owner"
                );
            }
        }
        /* Create borrow options */
        bytes memory borrowOptions = abi.encodePacked(uint16(1), uint16(encodedBundle.length), encodedBundle);

        /* Get yield pass amount */
        uint256 yieldPassAmount = IERC20(yp).balanceOf(address(smartAccount));

        /* Quote borrow principal */
        uint256 borrowPrincipal = yieldPassUtils.quoteBalancedLP(yp, address(ath), yieldPassAmount);

        /* Calls 2 */
        ICoinbaseSmartWallet.Call[] memory calls2 = new ICoinbaseSmartWallet.Call[](6);

        /* Validate slippage */
        calls2[0] = ICoinbaseSmartWallet.Call({
            target: address(yieldPassUtils),
            value: 0,
            data: abi.encodeWithSignature(
                "validateBalancedLP(address,address,uint256,uint256,uint64)",
                yp,
                address(ath),
                yieldPassAmount,
                borrowPrincipal,
                uint64(block.timestamp)
            )
        });

        /* Set approval */
        calls2[1] = ICoinbaseSmartWallet.Call({
            target: bundleCollateralWrapper,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", address(metaStreetPool), true)
        });

        /* Borrow */
        calls2[2] = ICoinbaseSmartWallet.Call({
            target: address(metaStreetPool),
            value: 0,
            data: abi.encodeWithSignature(
                "borrow(uint256,uint64,address,uint256,uint256,uint128[],bytes)",
                borrowPrincipal,
                metaStreetPool.durations()[0],
                bundleCollateralWrapper,
                bundleTokenId,
                borrowPrincipal,
                ticks,
                borrowOptions
            )
        });

        /* Set approvals */
        calls2[3] = ICoinbaseSmartWallet.Call({
            target: address(ath),
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", address(uniswapV2Router), type(uint256).max)
        });
        calls2[4] = ICoinbaseSmartWallet.Call({
            target: yp,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", address(uniswapV2Router), type(uint256).max)
        });

        /* Add liquidity */
        calls2[5] = ICoinbaseSmartWallet.Call({
            target: address(uniswapV2Router),
            value: 0,
            data: abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(yp),
                address(ath),
                yieldPassAmount,
                borrowPrincipal,
                1,
                1,
                address(smartAccount),
                block.timestamp
            )
        });

        /* Execute borrow and LP */
        smartAccount.executeBatch(calls2);

        vm.stopPrank();

        /* Check that pool ATH balance*/
        assertEq(
            IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance - borrowPrincipal, "Pool ATH balance wrong"
        );

        /* Check Uniswap liquidity tokens balances */
        assertGt(IERC20(pair).balanceOf(address(smartAccount)), 0, "Liquidator has no liquidity tokens");
        assertEq(IERC20(pair).balanceOf(address(yieldPassUtils)), 0, "Yield pass utils has no liquidity tokens");

        /* Check that pool ATH balance is lesser than before */
        assertLt(IERC20(ath).balanceOf(address(metaStreetPool)), poolAthBalance, "MetaStreetPool ATH balance wrong");
    }
}
