// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract UpgradeXaiYieldAdapter is Deployer {
    function run(address yieldPass, address xaiPoolFactory) public broadcast useDeployment returns (address) {
        /* Deploy new XaiYieldAdapter Implementation */
        console.log("Deploying XaiYieldAdapter implementation...");

        XaiYieldAdapter yieldAdapterImpl = new XaiYieldAdapter(yieldPass, xaiPoolFactory);

        console.log("XaiYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        console.log("Upgrading proxy %s implementation...", _deployment.xaiYieldAdapter);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.xaiYieldAdapter, ERC1967Utils.ADMIN_SLOT))));

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(_deployment.xaiYieldAdapter), address(yieldAdapterImpl), ""
        );

        console.log("Upgraded proxy %s implementation to: %s\n", _deployment.xaiYieldAdapter, address(yieldAdapterImpl));

        return address(yieldAdapterImpl);
    }
}
