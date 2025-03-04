// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {Vm} from "forge-std/Vm.sol";

import {PoolBaseTest} from "../../pool/Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {YieldPass} from "src/YieldPass.sol";
import {SophonYieldAdapter} from "src/yieldAdapters/sophon/SophonYieldAdapter.sol";
import {SimpleSmartAccountFactory} from "src/yieldAdapters/sophon/smartAccount/SimpleSmartAccountFactory.sol";
import {IGuardianDelegationProxy} from "src/yieldAdapters/sophon/SophonYieldAdapter.sol";
import {SimpleSmartAccount} from "src/yieldAdapters/sophon/smartAccount/SimpleSmartAccount.sol";
import {TestERC20} from "../../tokens/TestERC20.sol";
import {MockBundleCollateralWrapper} from "../../pool/MockBundleCollateralWrapper.sol";

/**
 * @title GuardianNFTProxy Interface
 */
interface IGuardianNFTProxy {
    function implementation() external view returns (address);
    function replaceImplementation(address newImplementation, bytes memory data) external;
    function batchMint(address[] memory receivers, uint256[] memory quantities, address validatorDelegate) external;
    function unpauseMinting() external;
    function increaseWhitelist(address[] memory users, uint256[] memory addedCounts) external;
    function toggleTransferWhitelist(address operator, bool canTransfer) external;
    function whitelist(
        address user
    ) external view returns (uint256);
    function name() external view returns (string memory);
}

interface IGuardianDelegation {
    enum DelegationType {
        Undefined,
        Validator,
        LightNode
    }

    struct Delegation {
        uint256 amount;
        uint256 lastUpdate;
        uint256 previousScore;
    }

    function _delegateOnMint(address sender, address receiver, uint256 maxAmount) external;
    function _removeAllOnBurn(
        address sender
    ) external;

    function removeDelegationAmount(
        DelegationType delegationType,
        address sender,
        uint256 removeAmount,
        bool ifNotFree
    ) external returns (uint256);

    function delegateToValidators(
        address[] memory receivers,
        uint256[] memory maxAmounts,
        bool partialFill
    ) external returns (uint256 delegations, uint256 totalDesired);
    function delegateToValidator(address receiver, uint256 maxAmount) external returns (uint256 delegations);

    function delegateToLightNode(address receiver, uint256 maxAmount) external returns (uint256 delegations);
    function delegateToLightNodes(
        address[] memory receivers,
        uint256[] memory maxAmounts,
        bool partialFill
    ) external returns (uint256 delegations, uint256 totalDesired);

    function balanceOfSent(
        address sender
    ) external view returns (uint256);
}

interface ISimpleSmartAccount {
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

interface ISimpleSmartAccountFactory {
    function createAccount() external payable returns (ISimpleSmartAccount);
    function getAddress(
        address owner
    ) external view returns (address);
}

interface ISwapRouter {
    struct TokenInput {
        address token;
        uint256 amount;
        bool useVault;
    }

    function createPool(address _factory, bytes calldata data) external payable returns (address);
    function addLiquidity2(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint256 minLiquidity,
        address callback,
        bytes calldata callbackData,
        address staking
    ) external payable returns (uint256 liquidity);
}

interface ISyncSwapPool {
    function getAssets() external view returns (address[] memory assets);
    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1);
    function vault() external view returns (address);
}

/**
 * @title Sophon base test setup
 *
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */
abstract contract SophonBaseTest is PoolBaseTest {
    string TESTNET_RPC_URL = vm.envString("TESTNET_RPC_URL");

    /* Guardian delegation */
    IGuardianDelegation internal guardianDelegationProxy =
        IGuardianDelegation(payable(0xF993Da47F610CaAE3bDdC479794B70306916B584));

    /* Smart wallet factory */
    ISimpleSmartAccountFactory internal smartWalletFactory;

    /* Node license */
    IERC721 internal sophonNodeLicense = IERC721(0xb28F859d67E1A690941CBE82BFE2d55f12CEe034);

    /* Sophon token */
    IERC20 internal sophonToken = IERC20(0x0000000000000000000000000000000000000000);

    /* Staking pool */
    address internal stakingPool1 = 0xB350456Aa5835F06446875179510a85cd4A6f9a7;

    /* Staking pool */
    address internal stakingPool2 = 0xCe17b4C6464Baded1635Cd0Dbd3889485959b009;

    /* Whitelist address */
    address internal whitelistAddress = 0x4a11165B9C815EdfbcB54D0B0dc1A295f74355D8;

    /* Admin address */
    address internal adminAddress = 0x78Ae12562527B865DD1a06784a2b06dbe1A3C7AF;

    /* Proxy admin */
    address internal proxyAdmin = 0x4cB9ac68A2151f14E8242a984b1F1faDb36EBF60;

    /* Classic pool factory */
    address internal classicPoolFactory = 0x701f3B10b5Cc30CA731fb97459175f45E0ac1247;

    /* Router */
    ISwapRouter internal router = ISwapRouter(0x5C07E74cB541c3D1875AEEE441D691DED6ebA204);

    uint64 internal startTime;
    uint64 internal expiry;

    /* WETH */
    IERC20 internal weth;

    /* Simple smart account */
    ISimpleSmartAccount internal smartAccount;

    /* Mock bundle collateral wrapper */
    address internal mockBundleCollateralWrapper;

    /* Sophon fork */
    uint256 sophonFork;
    IYieldAdapter internal yieldAdapterImpl;
    IYieldAdapter internal yieldAdapter;

    /* Node license owner */
    address internal snlOwner1;
    uint256 internal snlOwner1Pk;

    function setUp() public virtual override {
        sophonFork = vm.createSelectFork(TESTNET_RPC_URL);
        vm.selectFork(sophonFork);
        vm.rollFork(575638);

        PoolBaseTest.setUp();

        startTime = uint64(block.timestamp);
        expiry = startTime + 15 days;

        (snlOwner1, snlOwner1Pk) = makeAddrAndKey("SNL Owner 1");
        vm.deal({account: snlOwner1, newBalance: 100 ether});

        deployYieldAdapter();

        vm.startPrank(adminAddress);
        address[] memory whitelistedMinters = new address[](1);
        whitelistedMinters[0] = address(adminAddress);
        address[] memory receivers = new address[](1);
        receivers[0] = address(snlOwner1);
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 6;
        address validatorDelegate = stakingPool1;
        IGuardianNFTProxy(address(sophonNodeLicense)).increaseWhitelist(whitelistedMinters, quantities);

        vm.recordLogs();
        IGuardianNFTProxy(address(sophonNodeLicense)).batchMint(receivers, quantities, validatorDelegate);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 transferTopic = keccak256("Transfer(address,address,uint256)");
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == transferTopic && entries[i].topics.length == 4) {
                // uint256 tokenId = uint256(entries[i].topics[3]);
            }
        }

        vm.stopPrank();

        addWhitelist();
        deploySmartWalletFactory();
        createAccount();
        deployTestERC20();
        deployBundleCollateralWrapper();

        /* Approve license */
        vm.startPrank(snlOwner1);
        sophonNodeLicense.setApprovalForAll(address(yieldAdapter), true);
        sophonNodeLicense.setApprovalForAll(address(mockBundleCollateralWrapper), true);
        vm.stopPrank();
    }

    function deploySmartWalletFactory() internal {
        smartWalletFactory = ISimpleSmartAccountFactory(address(new SimpleSmartAccountFactory()));
        vm.label({account: address(smartWalletFactory), newLabel: "Simple Smart Account Factory"});
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

    function deployYieldAdapter() internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapter impl */
        yieldAdapterImpl =
            new SophonYieldAdapter(address(yieldPass), expiry, address(guardianDelegationProxy), address(sophonToken));

        /* Deploy yield adapter proxy */
        address[] memory lightNodes = new address[](2);
        lightNodes[0] = stakingPool1;
        lightNodes[1] = stakingPool2;
        yieldAdapter = SophonYieldAdapter(
            address(
                new ERC1967Proxy(
                    address(yieldAdapterImpl), abi.encodeWithSignature("initialize(address[],bool)", lightNodes, false)
                )
            )
        );

        vm.label({account: address(yieldAdapter), newLabel: "Sophon Yield Adapter"});

        vm.stopPrank();
    }

    function deployTestERC20() internal {
        vm.startPrank(snlOwner1);
        weth = IERC20(address(new TestERC20("Wrapped ETH", "WETH", 18, 200 ether)));

        vm.label({account: address(weth), newLabel: "WETH"});
        vm.stopPrank();
    }

    function deployBundleCollateralWrapper() internal {
        vm.startPrank(users.deployer);
        mockBundleCollateralWrapper = address(new MockBundleCollateralWrapper());

        vm.label({account: mockBundleCollateralWrapper, newLabel: "Mock Bundle Collateral Wrapper"});
        vm.stopPrank();
    }

    function generateStakingLightNodes(
        address[] memory lightNodes,
        uint256[] memory quantities
    ) internal pure returns (bytes memory) {
        return abi.encode(lightNodes, quantities);
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(snlOwner1Pk, hash);

        return abi.encodePacked(r, s, v);
    }

    function addWhitelist() internal {
        vm.startPrank(adminAddress);

        /* Add whitelist for node license */
        IGuardianNFTProxy(address(sophonNodeLicense)).toggleTransferWhitelist(address(yieldAdapter), true);

        vm.stopPrank();
    }

    function createAccount() internal {
        vm.startPrank(snlOwner1);
        smartAccount = smartWalletFactory.createAccount();

        vm.label({account: address(smartAccount), newLabel: "Simple Smart Account"});

        vm.stopPrank();
    }
}
