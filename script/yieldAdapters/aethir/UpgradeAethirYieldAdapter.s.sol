// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {AethirYieldAdapter} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract UpgradeAethirYieldAdapter is Deployer {
    function run(
        address proxy,
        uint64 yieldPassExpiry,
        address checkerNodeLicense,
        address checkerClaimAndWithdraw
    ) public broadcast useDeployment returns (address) {
        /* Deploy new AethirYieldAdapter Implementation */
        console.log("Deploying AethirYieldAdapter implementation...");

        AethirYieldAdapter yieldAdapterImpl =
            new AethirYieldAdapter(_deployment.yieldPass, yieldPassExpiry, checkerNodeLicense, checkerClaimAndWithdraw);

        console.log("AethirYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        console.log("Upgrading proxy %s implementation...", proxy);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(yieldAdapterImpl), "");

        console.log("Upgraded proxy %s implementation to: %s\n", proxy, address(yieldAdapterImpl));

        return address(yieldAdapterImpl);
    }
}
