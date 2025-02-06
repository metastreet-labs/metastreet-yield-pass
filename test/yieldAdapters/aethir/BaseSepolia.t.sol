// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {PoolBaseTest} from "../../pool/Base.t.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPoolFactory} from "metastreet-contracts-v2/interfaces/IPoolFactory.sol";
import {IPool} from "metastreet-contracts-v2/interfaces/IPool.sol";

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {CheckerLicenseNFT} from "src/yieldAdapters/aethir/CheckerLicenseNFT.sol";

import {YieldPass} from "src/YieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {AethirYieldAdapter, ICheckerClaimAndWithdraw, IERC4907} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import {MockCheckerClaimAndWithdraw} from "./mocks/MockCheckerClaimAndWithdraw.sol";

import "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";

interface IProxyAdminLegacy {
    function getProxyImplementation(
        ITransparentUpgradeableProxy proxy
    ) external view returns (address);
}

interface ICheckerLicenseNFT {
    function updateRecipientWhitelist(address[] calldata addressList, bool inWhitelist) external;
    function updateSenderWhitelist(address[] calldata addressList, bool inWhitelist) external;
    function updateWhitelistTransferTime(uint256 startTime, uint256 endTime) external;
}

interface ICoinbaseSmartWallet {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function execute(address target, uint256 value, bytes calldata data) external payable;
    function executeBatch(
        Call[] calldata calls
    ) external payable;
}

interface ICoinbaseSmartWalletFactory {
    function createAccount(
        bytes[] calldata owners,
        uint256 nonce
    ) external payable returns (ICoinbaseSmartWallet account);
}
/**
 * @title Aethir base test setup
 *
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */

abstract contract AethirSepoliaBaseTest is PoolBaseTest {
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    /* Smart wallet factory */
    ICoinbaseSmartWalletFactory internal smartWalletFactory =
        ICoinbaseSmartWalletFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);

    /* Uniswap V2 router */
    IUniswapV2Router02 internal uniswapV2Router = IUniswapV2Router02(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3);

    /* Uniswap V2 factory */
    IUniswapV2Factory internal uniswapV2Factory = IUniswapV2Factory(0xF62c03E08ada871A0bEb309762E260a7a6a880E6);

    /* Checker node license */
    address internal checkerNodeLicense = 0xc98A16E5244B051Bc1cF146c1f95cA9452007bcD;

    /* Checker node license owner of 776, 777, 778,779,780 */
    address internal cnlOwner = 0xa81acA2e31C071e8Ce2138200d966fE76Bcf0b71;

    /* Operator */
    address internal operator = 0xf0B90864CF8411Db83B62F1bb509137df992D785;

    /* EOA holding ATH */
    address internal athOwner = 0xdB246bc862bc88833a481339dFEb8311846E65de;

    /* Aethir token */
    IERC20 internal ath = IERC20(0x0Ce111bA243aeAe7976809Fc5F2feaa4eee65b2f);

    /* Checker claim and withdraw */
    address internal checkerClaimAndWithdraw = 0x91F5F7468e053c83Aa027C36585ea44Af81BA2f5;

    /* Admin address */
    address internal adminAddress = 0xBA733c086816f7eBD806cfD5AC38EaA5716d398C;

    /* Whitelist admin */
    address internal whitelistAdminAddress = 0x85BF1Dc2fA2d15AD45E8Fee07F95D7A811a9c013;

    /* Node signer */
    address internal nodeSigner;
    uint256 internal nodeSignerPk;

    /* Alternate cnl owner */
    address internal altCnlOwner;
    uint256 internal altCnlOwnerPk;

    uint64 internal startTime;
    uint64 internal expiry;

    uint256 sepoliaFork;
    IYieldAdapter internal yieldAdapterImpl;
    IYieldAdapter internal yieldAdapter;

    address internal mockCheckerClaimAndWithdraw;

    ICoinbaseSmartWallet internal smartAccount;

    function setUp() public virtual override {
        sepoliaFork = vm.createSelectFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaFork);
        vm.rollFork(6984216);

        PoolBaseTest.setUp();

        /* MetaStreet pool factory */
        metaStreetPoolFactory = IPoolFactory(0x5FC53D3C3B108aD1c1D27399AcB8124b65229eD6);

        /* MetaStreet pool impl */
        metaStreetPoolImpl = 0xAe36Eb66D1FEad713C61A8331D14F5B0E2562E93;

        /* Bundle collateral wrapper */
        bundleCollateralWrapper = 0x83c7bc92bcFF43b9F682B7C2eE897A7130a36543;

        (nodeSigner, nodeSignerPk) = makeAddrAndKey("Node Signer");

        (altCnlOwner, altCnlOwnerPk) = makeAddrAndKey("Alt CNL Owner");
        vm.deal({account: altCnlOwner, newBalance: 100 ether});

        /* Exclude 91526 from undelegation */
        uint256[] memory licenses = new uint256[](5);
        licenses[0] = 776;
        licenses[1] = 777;
        licenses[2] = 778;
        licenses[3] = 779;
        licenses[4] = 780;

        /* Undelegate licenses */
        vm.startPrank(cnlOwner);
        for (uint256 i = 0; i < licenses.length; i++) {
            IERC4907(checkerNodeLicense).setUser(licenses[i], address(0), 0);
        }
        vm.stopPrank();

        startTime = uint64(block.timestamp);
        expiry = startTime + 10 days;

        deployYieldAdapter(false, false);
        addWhitelist();

        vm.startPrank(cnlOwner);

        /* Approve license */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldAdapter), true);

        /* Delegate to operator */
        IERC4907(checkerNodeLicense).setUser(776, operator, expiry);
        IERC4907(checkerNodeLicense).setUser(777, operator, expiry);
        IERC4907(checkerNodeLicense).setUser(778, operator, expiry);
        IERC4907(checkerNodeLicense).setUser(779, operator, expiry);
        IERC4907(checkerNodeLicense).setUser(780, operator, expiry);
        vm.stopPrank();

        vm.startPrank(altCnlOwner);

        /* Approve license */
        IERC721(checkerNodeLicense).setApprovalForAll(address(yieldAdapter), true);

        /* Create smart account */
        createAccount();

        vm.stopPrank();
    }

    function deployYieldPass(
        address nft_,
        uint64 startTime_,
        uint64 expiry_,
        address yieldAdapter_
    ) internal returns (address yp, address np) {
        vm.startPrank(users.deployer);
        (yp, np) = yieldPass.deployYieldPass(nft_, startTime_, expiry_, yieldAdapter_);
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

    function deployYieldAdapter(bool isMock, bool isTransferUnlocked) internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapters */
        yieldAdapterImpl = new AethirYieldAdapter(
            address(yieldPass),
            expiry,
            address(checkerNodeLicense),
            isMock ? address(mockCheckerClaimAndWithdraw) : address(checkerClaimAndWithdraw)
        );

        /* Deploy yield adapter proxy */
        yieldAdapter = AethirYieldAdapter(
            address(
                new ERC1967Proxy(
                    address(yieldAdapterImpl),
                    abi.encodeWithSignature("initialize(uint48,address,bool)", 180 days, nodeSigner, isTransferUnlocked)
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
        address[] memory addressToList = new address[](2);
        addressToList[0] = address(yieldAdapter);
        addressToList[1] = address(altCnlOwner);
        bool inToWhitelist = true;

        /* Add whitelist for node license */
        ICheckerLicenseNFT(checkerNodeLicense).updateSenderWhitelist(addressFromList, inFromWhitelist);
        ICheckerLicenseNFT(checkerNodeLicense).updateRecipientWhitelist(addressToList, inToWhitelist);

        ICheckerLicenseNFT(checkerNodeLicense).updateWhitelistTransferTime(block.timestamp, block.timestamp + 10 days);

        vm.stopPrank();
    }

    function generateSignedNodes(
        address operator_,
        uint256[] memory tokenIds,
        uint64 timestamp,
        uint64 duration,
        uint64 subscriptionExpiry
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Aethir Yield Adapter")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(yieldAdapter)
            )
        );

        address[] memory burnerWallets = new address[](tokenIds.length);
        uint64[] memory subscriptionExpiries = new uint64[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            burnerWallets[i] = operator_;
            subscriptionExpiries[i] = subscriptionExpiry;
        }

        bytes memory encodedTokenIds;
        bytes memory encodedBurnerWallets;
        bytes memory encodedSubscriptionExpiries;
        for (uint256 i; i < tokenIds.length; i++) {
            /* Encode token ID */
            encodedTokenIds = bytes.concat(encodedTokenIds, abi.encode(tokenIds[i]));

            /* Encode burner wallet */
            encodedBurnerWallets = bytes.concat(encodedBurnerWallets, abi.encode(burnerWallets[i]));

            /* Encode subscription expiry */
            encodedSubscriptionExpiries = bytes.concat(encodedSubscriptionExpiries, abi.encode(subscriptionExpiries[i]));
        }

        bytes32 structHash = keccak256(
            abi.encode(
                AethirYieldAdapter(address(yieldAdapter)).VALIDATED_NODES_TYPEHASH(),
                keccak256(encodedTokenIds),
                keccak256(encodedBurnerWallets),
                keccak256(encodedSubscriptionExpiries),
                timestamp,
                duration
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nodeSignerPk, hash);

        AethirYieldAdapter.SignedValidatedNodes memory signedValidatedNodes = AethirYieldAdapter.SignedValidatedNodes({
            nodes: AethirYieldAdapter.ValidatedNodes({
                tokenIds: tokenIds,
                burnerWallets: burnerWallets,
                subscriptionExpiries: subscriptionExpiries,
                timestamp: timestamp,
                duration: duration
            }),
            signature: abi.encodePacked(r, s, v)
        });

        return abi.encode(signedValidatedNodes);
    }

    function generateHarvestData(
        bool isClaim,
        uint256 count,
        uint48 orderExpiryTimestamp,
        bool withError
    ) internal pure returns (bytes memory) {
        /* Generate claim data */
        if (isClaim) {
            AethirYieldAdapter.AethirClaimData[] memory claimData = new AethirYieldAdapter.AethirClaimData[](count);
            for (uint256 i = 0; i < count; i++) {
                claimData[i] = AethirYieldAdapter.AethirClaimData({
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

        AethirYieldAdapter.AethirWithdrawData memory withdrawData = AethirYieldAdapter.AethirWithdrawData({
            orderIdArray: orderIdArray,
            expiryTimestamp: orderExpiryTimestamp,
            signatureArray: new bytes[](count)
        });

        return abi.encode(false, abi.encode(withdrawData));
    }

    function generateTransferSignature(
        address smartAccount_,
        uint256 deadline,
        uint256[] memory tokenIds
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("MetaStreet Yield Pass")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(yieldPass)
            )
        );

        /* Encode token IDs */
        bytes memory encodedTokenIds;
        for (uint256 i; i < tokenIds.length; i++) {
            encodedTokenIds = bytes.concat(encodedTokenIds, abi.encode(tokenIds[i]));
        }

        bytes32 structHash = keccak256(
            abi.encode(
                YieldPass(address(yieldPass)).TRANSFER_APPROVAL_TYPEHASH(),
                smartAccount_,
                deadline,
                keccak256(encodedTokenIds)
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(altCnlOwnerPk, hash);

        return abi.encodePacked(r, s, v);
    }

    function createAccount() internal {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(altCnlOwner);

        smartAccount = smartWalletFactory.createAccount(owners, 0);
    }
}
