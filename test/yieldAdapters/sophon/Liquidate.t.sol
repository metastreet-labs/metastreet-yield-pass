// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {SophonBaseTest, ISimpleSmartAccount, ISwapRouter, ISyncSwapPool} from "./BaseSophon.t.sol";
import {BaseTest} from "../../pool/Base.t.sol";
import {PoolBaseTest} from "../../pool/Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import {SophonYieldAdapter} from "src/yieldAdapters/sophon/SophonYieldAdapter.sol";

import {Helpers} from "../../pool/Helpers.sol";

import "forge-std/console.sol";

contract LiquidateTest is SophonBaseTest {
    address internal yp;
    address internal np;
    uint128 internal tick;
    address internal pair;
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

        PoolBaseTest.deployMockMetaStreetPool(address(weth));
        setUpSyncSwap();
        setUpMSPool();
    }

    function setUpSyncSwap() internal {
        vm.startPrank(snlOwner1);

        /* Mint to get some yield pass tokens */
        yieldPass.mint(
            yp,
            snlOwner1,
            snlOwner1,
            snlOwner1,
            block.timestamp,
            tokenIds3,
            generateStakingLightNodes(stakingPools1, quantities2),
            ""
        );

        /* Create pool */
        pair = router.createPool(classicPoolFactory, abi.encode(address(yp), address(weth)));

        /* Approve uniswap router */
        IERC20(yp).approve(address(router), type(uint256).max);
        IERC20(weth).approve(address(router), type(uint256).max);

        ISwapRouter.TokenInput[] memory inputs = new ISwapRouter.TokenInput[](2);
        inputs[0] = ISwapRouter.TokenInput({token: address(yp), amount: 1 ether, useVault: false});
        inputs[1] = ISwapRouter.TokenInput({token: address(weth), amount: 1 ether, useVault: false});

        /* Add liquidity */
        router.addLiquidity2(pair, inputs, abi.encode(address(snlOwner1)), 0, address(0), "", address(0));

        vm.stopPrank();
    }

    function setUpMSPool() internal {
        /* Transfer some weth to CNL owner */
        vm.startPrank(snlOwner1);

        /* Transfer weth to mock MS pool */
        IERC20(weth).transfer(address(metaStreetPool), 100 ether);

        vm.stopPrank();
    }

    function test__MintAndLP() external {
        vm.startPrank(snlOwner1);
        guardianDelegationProxy.delegateToLightNodes(stakingPools1, quantities2, false);

        /* Generate setup data */
        bytes memory setupData = generateStakingLightNodes(stakingPools1, quantities2);

        /* Get ticks */
        uint128[] memory ticks = new uint128[](1);
        ticks[0] = Helpers.encodeTick(100 ether, 0, 0, 0);

        /* Generate transfer signature */
        uint256 deadline = block.timestamp + 1 days;
        bytes memory transferSignature = generateTransferSignature(address(smartAccount), deadline, tokenIds2);

        /* Pool weth balance */
        uint256 poolWethBalance = IERC20(weth).balanceOf(address(metaStreetPool));

        /* Calls 1 */
        ISimpleSmartAccount.Call[] memory calls1 = new ISimpleSmartAccount.Call[](4);

        /* Mint 2 node licenses */
        calls1[0] = ISimpleSmartAccount.Call({
            target: address(yieldPass),
            value: 0,
            data: abi.encodeWithSignature(
                "mint(address,address,address,address,uint256,uint256[],bytes,bytes)",
                yp,
                snlOwner1,
                address(smartAccount),
                address(smartAccount),
                deadline,
                tokenIds2,
                setupData,
                transferSignature
            )
        });

        /* Set approval for NPs for bundle collateral wrapper */
        calls1[1] = ISimpleSmartAccount.Call({
            target: np,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", mockBundleCollateralWrapper, true)
        });

        /* Bundle NPs */
        calls1[2] = ISimpleSmartAccount.Call({
            target: mockBundleCollateralWrapper,
            value: 0,
            data: abi.encodeWithSignature("mint(address,uint256[])", np, tokenIds2)
        });

        /* Unset approval for bundle collateral wrapper for NP */
        calls1[3] = ISimpleSmartAccount.Call({
            target: np,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", mockBundleCollateralWrapper, false)
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
                    IERC721(mockBundleCollateralWrapper).ownerOf(bundleTokenId),
                    address(smartAccount),
                    "Invalid NFT owner"
                );
            }
        }
        /* Create borrow options */
        bytes memory borrowOptions = abi.encodePacked(uint16(1), uint16(encodedBundle.length), encodedBundle);

        /* Get yield pass amount */
        uint256 yieldPassAmount = IERC20(yp).balanceOf(address(smartAccount));

        /* Get Uniswap V2 pair reserves */
        (uint256 reserveA, uint256 reserveB) = ISyncSwapPool(pair).getReserves();

        /* Quote borrow principal */
        uint256 borrowPrincipal = Math.mulDiv(yieldPassAmount, reserveB, reserveA);

        /* Calls 2 */
        ISimpleSmartAccount.Call[] memory calls2 = new ISimpleSmartAccount.Call[](5);

        /* Set approval */
        calls2[0] = ISimpleSmartAccount.Call({
            target: mockBundleCollateralWrapper,
            value: 0,
            data: abi.encodeWithSignature("setApprovalForAll(address,bool)", address(metaStreetPool), true)
        });

        /* Borrow */
        calls2[1] = ISimpleSmartAccount.Call({
            target: address(metaStreetPool),
            value: 0,
            data: abi.encodeWithSignature(
                "borrow(uint256,uint64,address,uint256,uint256,uint128[],bytes)",
                borrowPrincipal,
                0,
                mockBundleCollateralWrapper,
                bundleTokenId,
                borrowPrincipal,
                ticks,
                borrowOptions
            )
        });

        /* Set approvals */
        calls2[2] = ISimpleSmartAccount.Call({
            target: address(weth),
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", address(router), type(uint256).max)
        });
        calls2[3] = ISimpleSmartAccount.Call({
            target: yp,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", address(router), type(uint256).max)
        });

        ISwapRouter.TokenInput[] memory inputs = new ISwapRouter.TokenInput[](2);
        inputs[0] = ISwapRouter.TokenInput({token: address(yp), amount: yieldPassAmount, useVault: false});
        inputs[1] = ISwapRouter.TokenInput({token: address(weth), amount: borrowPrincipal, useVault: false});

        /* Add liquidity */
        calls2[4] = ISimpleSmartAccount.Call({
            target: address(router),
            value: 0,
            data: abi.encodeWithSelector(
                ISwapRouter.addLiquidity2.selector,
                pair,
                inputs,
                abi.encode(address(smartAccount)),
                0,
                address(0),
                "",
                address(0)
            )
        });

        /* Execute borrow and LP */
        smartAccount.executeBatch(calls2);

        vm.stopPrank();

        /* Check that pool weth balance*/
        assertEq(
            IERC20(weth).balanceOf(address(metaStreetPool)),
            poolWethBalance - borrowPrincipal,
            "Pool weth balance wrong"
        );

        /* Check Uniswap liquidity tokens balances */
        assertGt(IERC20(pair).balanceOf(address(smartAccount)), 0, "Liquidator has no liquidity tokens");

        /* Check that pool weth balance is lesser than before */
        assertLt(IERC20(weth).balanceOf(address(metaStreetPool)), poolWethBalance, "MetaStreetPool weth balance wrong");
    }
}
