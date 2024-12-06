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
import {NodeLicense} from "src/yieldAdapters/xai/NodeLicense.sol";

interface IProxyAdminLegacy {
    function getProxyImplementation(
        ITransparentUpgradeableProxy proxy
    ) external view returns (address);
}

interface IReferee {
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

/**
 * @title XAI base test setup
 *
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */
abstract contract XaiBaseTest is PoolBaseTest {
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    /* Sentry node license */
    IERC721 internal sentryNodeLicense = IERC721(0xbc14d8563b248B79689ECbc43bBa53290e0b6b66);

    /* Sentry node license owner of 19727, 19728, 19729, 19730, 21017, 22354, 22355 */
    address internal snlOwner = 0x98AEDc32d5194b3b0b973b9467520F3C40669805;

    /* EOA holding esXAI */
    address internal esXaiOwner = 0xf0B90864CF8411Db83B62F1bb509137df992D785;

    IERC20 internal esXai = IERC20(0x4C749d097832DE2FEcc989ce18fDc5f1BD76700c);

    /* XAI token */
    IERC20 internal xai = IERC20(0x4Cb9a7AE498CEDcBb5EAe9f25736aE7d428C9D66);

    /* XAI pool factory */
    IPoolFactory internal poolFactory = IPoolFactory(0xF9E08660223E2dbb1c0b28c82942aB6B5E38b8E5);

    /* Staking pool: Mc ALPHA 2 */
    address internal stakingPool = 0x57C36988d0134b4998B1Fda3A55FcABdBF348F42;

    /* XAI referee */
    IReferee internal xaiReferee = IReferee(0xfD41041180571C5D371BEA3D9550E55653671198);

    /* KYC role */
    address internal kycRole = 0x7eC7e03563f781ED4c56BBC4c5F28C1B4dB932ff;

    /* Proxy admin */
    address internal proxyAdmin = 0xD88c8E0aE21beA6adE41A41130Bb4cd43e6b1723;

    /* Admin address */
    address internal adminAddress = 0x7C94E07bbf73518B0E25D1Be200a5b58F46F9dC7;

    uint64 internal startTime;
    uint64 internal expiry;

    uint256 arbitrumFork;
    IYieldAdapter internal yieldAdapterImpl;
    IYieldAdapter internal yieldAdapter;

    function setUp() public virtual override {
        arbitrumFork = vm.createSelectFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.rollFork(257363089);

        PoolBaseTest.setUp();

        /* Exclude 22355 from unstaking */
        uint256[] memory licenses = new uint256[](6);
        licenses[0] = 19727;
        licenses[1] = 19728;
        licenses[2] = 19729;
        licenses[3] = 19730;
        licenses[4] = 21017;
        licenses[5] = 22354;

        /* Unstake licenses */
        vm.startPrank(snlOwner);
        poolFactory.createUnstakeKeyRequest(stakingPool, 6);
        uint256 unstakeRequestIndex = IPool(stakingPool).getUnstakeRequestCount(snlOwner) - 1;
        vm.warp(block.timestamp + poolFactory.unstakeKeysDelayPeriod());
        poolFactory.unstakeKeys(stakingPool, unstakeRequestIndex, licenses);
        vm.stopPrank();

        /* Approve license */
        vm.startPrank(snlOwner);
        sentryNodeLicense.setApprovalForAll(address(yieldPass), true);
        vm.stopPrank();

        startTime = uint64(block.timestamp);
        expiry = startTime + 10 days;

        upgradeNodeLicense();
        deployYieldAdapter();
        addKyc(address(yieldAdapter));
        addWhitelist();
    }

    function deployYieldPass(
        address nft_,
        uint64 startTime_,
        uint64 expiry_,
        address yieldAdapter_
    ) internal returns (address yp, address dp) {
        vm.startPrank(users.deployer);
        (yp, dp) = yieldPass.deployYieldPass(nft_, startTime_, expiry_, false, yieldAdapter_);
        vm.stopPrank();
    }

    function deployYieldAdapter() internal {
        vm.startPrank(users.deployer);

        /* Deploy yield adapter impl */
        yieldAdapterImpl = new XaiYieldAdapter(address(yieldPass), address(poolFactory));

        /* Deploy yield adapter proxy */
        address[] memory pools = new address[](1);
        pools[0] = stakingPool;
        yieldAdapter = XaiYieldAdapter(
            address(
                new ERC1967Proxy(address(yieldAdapterImpl), abi.encodeWithSignature("initialize(address[])", pools))
            )
        );
        vm.label({account: address(yieldAdapter), newLabel: "XAI Yield Adapter"});

        vm.stopPrank();
    }

    function upgradeNodeLicense() internal {
        ITransparentUpgradeableProxy proxyAddress = ITransparentUpgradeableProxy(address(sentryNodeLicense));

        /* Deploy new implementation */
        address newImplementation = address(new NodeLicense());

        /* Upgrade proxy to new implementation */
        vm.startPrank(adminAddress);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            proxyAddress,
            newImplementation,
            abi.encodeWithSelector(NodeLicense.initialize.selector, address(xaiReferee))
        );

        /* Verify upgrade */
        address newImplementationAddress = IProxyAdminLegacy(proxyAdmin).getProxyImplementation(proxyAddress);
        require(newImplementationAddress == newImplementation, "Upgrade failed");

        vm.stopPrank();
    }

    function generateStakingPools(
        address pool
    ) internal pure returns (bytes memory) {
        return abi.encode(pool);
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

    function addWhitelist() internal {
        vm.startPrank(adminAddress);
        /* Add whitelist for node license */
        NodeLicense(address(sentryNodeLicense)).addToWhitelist(address(yieldAdapter));

        /* Add whitelist for esXAI */
        IEsXai(address(esXai)).addToWhitelist(address(yieldAdapter));
        IEsXai(address(esXai)).addToWhitelist(address(yieldPass));
        vm.stopPrank();
    }
}
