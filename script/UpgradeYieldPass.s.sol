// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {YieldPass} from "src/YieldPass.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeYieldPass is Deployer {
    function run() public broadcast useDeployment returns (address) {
        /* Deploy new YieldPass Implementation */
        console.log("Deploying YieldPass implementation...");

        YieldPass yieldPassImpl = new YieldPass();

        console.log("YieldPass implementation deployed at: %s\n", address(yieldPassImpl));

        console.log("Upgrading proxy %s implementation...", _deployment.yieldPass);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.yieldPass, ERC1967Utils.ADMIN_SLOT))));

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(_deployment.yieldPass), address(yieldPassImpl), ""
        );

        console.log("Upgraded proxy %s implementation to: %s\n", _deployment.yieldPass, address(yieldPassImpl));

        return address(yieldPassImpl);
    }
}
