// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract UpgradeXaiYieldAdapter is Deployer {
    function run(
        address proxy,
        uint64 yieldPassExpiry,
        address xaiPoolFactory
    ) public broadcast useDeployment returns (address) {
        /* Deploy new XaiYieldAdapter Implementation */
        console.log("Deploying XaiYieldAdapter implementation...");

        XaiYieldAdapter yieldAdapterImpl = new XaiYieldAdapter(_deployment.yieldPass, yieldPassExpiry, xaiPoolFactory);

        console.log("XaiYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        console.log("Upgrading proxy %s implementation...", proxy);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(yieldAdapterImpl), "");
            console.log("Upgraded proxy %s implementation to: %s\n", proxy, address(yieldAdapterImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(proxy),
                    address(yieldAdapterImpl),
                    ""
                )
            );
        }

        return address(yieldAdapterImpl);
    }
}
