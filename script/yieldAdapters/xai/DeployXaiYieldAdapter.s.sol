// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract DeployXaiYieldAdapter is Deployer {
    function run(
        uint64 yieldPassExpiry,
        address xaiPoolFactory,
        bool isTransferUnlocked
    ) public broadcast useDeployment returns (address) {
        if (_deployment.yieldPass == address(0)) revert MissingDependency();

        /* XaiYieldAdapter Implementation */
        console.log("Deploying XaiYieldAdapter implementation...");

        XaiYieldAdapter yieldAdapterImpl = new XaiYieldAdapter(_deployment.yieldPass, yieldPassExpiry, xaiPoolFactory);

        console.log("XaiYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        /* XaiYieldAdapter Proxy */
        console.log("Deploying XaiYieldAdapter proxy...");

        address[] memory pools = new address[](0);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(yieldAdapterImpl),
            msg.sender,
            abi.encodeWithSignature("initialize(address[],bool)", pools, isTransferUnlocked)
        );

        console.log("XaiYieldAdapter proxy deployed at: %s\n", address(proxy));

        return address(proxy);
    }
}
