// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {BaseTest} from "../Base.t.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CheckerLicenseNFT} from "src/yieldAdapters/aethir/CheckerLicenseNFT.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {AethirYieldAdapter, ICheckerClaimAndWithdraw, IERC4907} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import {MockCheckerClaimAndWithdraw} from "./mocks/MockCheckerClaimAndWithdraw.sol";

interface IProxyAdminLegacy {
    function getProxyImplementation(ITransparentUpgradeableProxy proxy) external view returns (address);
}

/**
 * @title Aethir base test setup
 *
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */
abstract contract AethirBaseTest is BaseTest {
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    /* Checker node license */
    address internal checkerNodeLicense = 0xC227e25544EdD261A9066932C71a25F4504972f1;

    /* Checker node license owner of 91521, 91522, 91523, 91524, 91525, 91526 */
    address internal cnlOwner = 0x89D07bF06674f1eAc72bAcE3E16B9567bA1197f9;

    /* Operator */
    address internal operator = 0xf0B90864CF8411Db83B62F1bb509137df992D785;

    /* EOA holding ATH */
    address internal athOwner = 0x0de5c1C03FdbC41b5995b4e2B0A9938b391569a8;

    /* Aethir token */
    IERC20 internal ath = IERC20(0xc87B37a581ec3257B734886d9d3a581F5A9d056c);

    /* Checker claim and withdraw */
    address internal checkerClaimAndWithdraw = 0x3EB64fc76De5D77659387E64951d78d5fCaE1111;

    /* Admin address */
    address internal adminAddress = 0xBA733c086816f7eBD806cfD5AC38EaA5716d398C;

    /* Whitelist admin */
    address internal whitelistAdminAddress = 0xF6A9359488C583Be23e2Fd18D782075E3070196A;

    /* Yield adapter name */
    string internal yieldAdapterName = "Aethir Yield Adapter";

    /* Node signer */
    address internal nodeSigner;
    uint256 internal nodeSignerPk;

    uint64 internal startTime;
    uint64 internal expiry;

    uint256 arbitrumFork;
    IYieldAdapter internal yieldAdapterImpl;
    IYieldAdapter internal yieldAdapter;

    address internal mockCheckerClaimAndWithdraw;

    function setUp() public virtual override {
        arbitrumFork = vm.createSelectFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.rollFork(257363089);

        BaseTest.setUp();

        (nodeSigner, nodeSignerPk) = makeAddrAndKey("Node Signer");

        /* Exclude 91526 from undelegation */
        uint256[] memory licenses = new uint256[](5);
        licenses[0] = 91521;
        licenses[1] = 91522;
        licenses[2] = 91523;
        licenses[3] = 91524;
        licenses[4] = 91525;

        /* Undelegate licenses */
        vm.startPrank(cnlOwner);
        for (uint256 i = 0; i < licenses.length; i++) {
            IERC4907(checkerNodeLicense).setUser(licenses[i], address(0), 0);
        }
        vm.stopPrank();

        startTime = uint64(block.timestamp);
        expiry = startTime + 10 days;

        vm.startPrank(cnlOwner);

        /* Approve license */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldPass), true);

        /* Delegate to operator */
        IERC4907(checkerNodeLicense).setUser(91521, operator, expiry + 1);
        IERC4907(checkerNodeLicense).setUser(91522, operator, expiry + 1);
        IERC4907(checkerNodeLicense).setUser(91523, operator, expiry + 1);
        IERC4907(checkerNodeLicense).setUser(91524, operator, expiry + 1);
        IERC4907(checkerNodeLicense).setUser(91525, operator, expiry);
        vm.stopPrank();

        upgradeNodeLicense();
        deployYieldAdapter(false);
        addWhitelist();
    }

    function deployYieldPass(
        address nft_,
        uint64 startTime_,
        uint64 expiry_,
        address yieldAdapter_
    ) internal returns (address yp, address dp) {
        vm.startPrank(users.deployer);
        (yp, dp) = yieldPass.deployYieldPass(nft_, startTime_, expiry_, true, yieldAdapter_);
        vm.stopPrank();
    }

    function deployMockCheckerClaimAndWithdraw() internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapters */
        address[] memory operators = new address[](1);
        operators[0] = operator;

        mockCheckerClaimAndWithdraw = address(new MockCheckerClaimAndWithdraw(address(ath)));
        vm.label({account: mockCheckerClaimAndWithdraw, newLabel: "mockCheckerClaimAndWithdraw"});

        vm.stopPrank();
    }

    function deployYieldAdapter(bool isMock) internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapters */
        yieldAdapterImpl = new AethirYieldAdapter(
            yieldAdapterName,
            address(yieldPass),
            address(checkerNodeLicense),
            isMock ? address(mockCheckerClaimAndWithdraw) : address(checkerClaimAndWithdraw),
            address(ath)
        );

        /* Deploy yield adapter proxy */
        yieldAdapter = AethirYieldAdapter(
            address(
                new ERC1967Proxy(
                    address(yieldAdapterImpl),
                    abi.encodeWithSignature("initialize(uint48,address)", 180 days, nodeSigner)
                )
            )
        );
        vm.label({account: address(yieldAdapter), newLabel: "Aethir Yield Adapter"});

        vm.stopPrank();
    }

    function upgradeNodeLicense() internal {
        ITransparentUpgradeableProxy proxyAddress = ITransparentUpgradeableProxy(address(checkerNodeLicense));

        /* Deploy new implementation */
        address newImplementation = address(new CheckerLicenseNFT());

        /* Upgrade proxy to new implementation */
        vm.startPrank(adminAddress);
        proxyAddress.upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function addWhitelist() internal {
        vm.startPrank(whitelistAdminAddress);

        /* Update from whitelist */
        address[] memory addressFromList = new address[](1);
        addressFromList[0] = address(yieldAdapter);
        bool inFromWhitelist = true;

        /* Update to whitelist */
        address[] memory addressToList = new address[](1);
        addressToList[0] = address(yieldAdapter);
        bool inToWhitelist = true;

        /* Add whitelist for node license */
        CheckerLicenseNFT(checkerNodeLicense).updateTransferWhiteList(
            addressFromList, inFromWhitelist, addressToList, inToWhitelist
        );

        vm.stopPrank();
    }

    function generateSignedNode(
        address operator_,
        uint256 tokenId,
        uint64 timestamp,
        uint64 duration
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(yieldAdapterName)),
                keccak256(bytes("1.0")),
                block.chainid,
                address(yieldAdapter)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                AethirYieldAdapter(address(yieldAdapter)).NODE_TYPEHASH(), tokenId, operator_, timestamp, duration
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nodeSignerPk, hash);

        AethirYieldAdapter.SignedNode memory signedNode = AethirYieldAdapter.SignedNode({
            node: AethirYieldAdapter.ValidatedNode({
                tokenId: tokenId,
                burnerWallet: operator_,
                timestamp: timestamp,
                duration: duration
            }),
            signature: abi.encodePacked(r, s, v)
        });

        return abi.encode(signedNode);
    }

    function generateHarvestData(
        bool isClaim,
        uint256 count,
        uint48 orderExpiryTimestamp,
        bool withError
    ) internal pure returns (bytes memory) {
        /* Generate claim data */
        if (isClaim) {
            AethirYieldAdapter.ClaimData[] memory claimData = new AethirYieldAdapter.ClaimData[](count);
            for (uint256 i = 0; i < count; i++) {
                claimData[i] = AethirYieldAdapter.ClaimData({
                    orderId: i + 1,
                    cliffSeconds: withError ? 180 days - 1 : 180 days,
                    expiryTimestamp: orderExpiryTimestamp,
                    amount: 1_000_000,
                    signatureArray: new bytes[](0)
                });
            }

            return abi.encode(true, abi.encode(claimData));
        }

        /* Generate withdraw data */
        uint256[] memory orderIdArray = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIdArray[i] = i + 1;
        }

        AethirYieldAdapter.WithdrawData memory withdrawData = AethirYieldAdapter.WithdrawData({
            orderIdArray: orderIdArray,
            expiryTimestamp: orderExpiryTimestamp,
            signatureArray: new bytes[](count)
        });

        return abi.encode(false, abi.encode(withdrawData));
    }
}
