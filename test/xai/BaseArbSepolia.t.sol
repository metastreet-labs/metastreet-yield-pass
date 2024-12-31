// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {PoolBaseTest} from "../pool/Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {XaiYieldAdapter, IPoolFactory, IPool} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";

interface IReferee {
    function grantRole(bytes32 role, address account) external;
    function addKycWallet(
        address wallet
    ) external;
    function removeKycWallet(
        address account
    ) external;
}

interface IEsXai {
    function addToWhitelist(
        address account
    ) external;
}

interface INodeLicense {
    function grantRole(bytes32 role, address account) external;
}

/**
 * @title XAI base test setup
 *
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */
abstract contract XaiBaseTest is PoolBaseTest {
    string ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");

    /* Sentry node license */
    IERC721 internal sentryNodeLicense = IERC721(0x07C05C6459B0F86A6aBB3DB71C259595d22af3C2);

    /* Sentry node license owner of 123714, 123713, 123712, 123711, 122443, 122444, 122445 */
    address internal snlOwner1 = 0x12e0d70Fa6554BA7e3Fc7Fe5AFd400fC0A18C34C;

    /* Sentry node license owner of 130606, 130605, 130604, 130603, 130602, 130601, 130600 */
    address internal snlOwner2 = 0x9cb34044A8139EEd288dF9556B398e91c76f2C64;

    /* EOA holding esXAI */
    address internal esXaiOwner = 0x1e7238C45C80e45b5D33b3b6D647427146bE1366;

    IERC20 internal esXai = IERC20(0x5776784C2012887D1f2FA17281E406643CBa5330);

    /* XAI token */
    IERC20 internal xai = IERC20(0x724E98F16aC707130664bb00F4397406F74732D0);

    /* XAI pool factory */
    IPoolFactory internal poolFactory = IPoolFactory(0x87Ae2373007C01FBCED0dCCe4a23CA3f17D1fA9A);

    /* Staking pool (snlOwner1 has 3442 staked licenses) */
    address internal stakingPool1 = 0x2D8903cEB90342C991DfC644B596492C6113BD4D;

    /* Staking pool (snlOwner2 has 12743 staked license) */
    address internal stakingPool2 = 0xCe17b4C6464Baded1635Cd0Dbd3889485959b009;

    /* XAI referee */
    IReferee internal xaiReferee = IReferee(0xF84D76755a68bE9DFdab9a0b6d934896Ceab957b);

    /* KYC role */
    address internal kycRole = 0x54E9CFF378dAF818D082fE9764e15470f34058D2;

    /* Admin address */
    address internal adminAddress = 0x490A5C858458567Bd58774C123250de11271f165;

    uint64 internal startTime;
    uint64 internal expiry;

    uint256 arbitrumFork;
    IYieldAdapter internal yieldAdapterImpl;
    IYieldAdapter internal yieldAdapter;

    function setUp() public virtual override {
        arbitrumFork = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.rollFork(112058244);

        PoolBaseTest.setUp();

        /* Unstake and stake licenses */
        vm.startPrank(snlOwner1);
        poolFactory.unstakeKeys(stakingPool1, 0);
        poolFactory.stakeKeys(stakingPool1, 3442);
        vm.stopPrank();

        deployYieldAdapter();
        grantKycAdminRole();
        addWhitelist();
        addKyc(address(yieldAdapter));
        addKyc(snlOwner2);
        grantTransferRole();

        /* Approve license */
        vm.startPrank(snlOwner1);
        sentryNodeLicense.setApprovalForAll(address(yieldAdapter), true);
        vm.stopPrank();

        vm.startPrank(snlOwner2);
        sentryNodeLicense.setApprovalForAll(address(yieldAdapter), true);
        vm.stopPrank();

        startTime = uint64(block.timestamp);
        expiry = startTime + 15 days;
    }

    function deployYieldPass(
        address nft_,
        uint64 startTime_,
        uint64 expiry_,
        address yieldAdapter_
    ) internal returns (address yp, address np) {
        vm.startPrank(users.deployer);
        (yp, np) = yieldPass.deployYieldPass(nft_, startTime_, expiry_, false, yieldAdapter_);
        vm.stopPrank();
    }

    function deployYieldAdapter() internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapter impl */
        yieldAdapterImpl = new XaiYieldAdapter(address(yieldPass), address(poolFactory));

        /* Deploy yield adapter proxy */
        address[] memory pools = new address[](2);
        pools[0] = stakingPool1;
        pools[1] = stakingPool2;
        yieldAdapter = XaiYieldAdapter(
            address(
                new ERC1967Proxy(address(yieldAdapterImpl), abi.encodeWithSignature("initialize(address[])", pools))
            )
        );
        vm.label({account: address(yieldAdapter), newLabel: "XAI Yield Adapter"});

        vm.stopPrank();
    }

    function generateStakingPools(
        address[] memory pools,
        uint256[] memory quantities
    ) internal pure returns (bytes memory) {
        return abi.encode(pools, quantities);
    }

    function addWhitelist() internal {
        vm.startPrank(adminAddress);

        /* Add whitelist for esXAI */
        IEsXai(address(esXai)).addToWhitelist(address(yieldAdapter));
        IEsXai(address(esXai)).addToWhitelist(address(yieldPass));
        vm.stopPrank();
    }

    function grantKycAdminRole() internal {
        vm.startPrank(adminAddress);
        bytes32 kycAdminRole = keccak256("KYC_ADMIN_ROLE");
        xaiReferee.grantRole(kycAdminRole, kycRole);
        vm.stopPrank();
    }

    function addKyc(
        address account
    ) internal {
        /* KYC user */
        vm.prank(kycRole);
        xaiReferee.addKycWallet(account);
    }

    function removeKyc(
        address account
    ) internal {
        /* KYC user */
        vm.prank(kycRole);
        xaiReferee.removeKycWallet(account);
    }

    function grantTransferRole() internal {
        vm.startPrank(adminAddress);
        bytes32 transferRole = keccak256("TRANSFER_ROLE");

        /* Grant transfer role */
        INodeLicense(address(sentryNodeLicense)).grantRole(transferRole, address(yieldAdapter));

        vm.stopPrank();
    }
}
