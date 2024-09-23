// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {YieldPass} from "src/YieldPass.sol";
import {Deployer} from "script/utils/Deployer.s.sol";

contract DeployYieldPass is Deployer {
    function run() public broadcast useDeployment returns (address) {
        if (_deployment.yieldPass != address(0)) revert AlreadyDeployed();

        /* YieldPass Implementation */
        console.log("Deploying YieldPass implementation...");

        YieldPass yieldPassImpl = new YieldPass();

        console.log("YieldPass implementation deployed at: %s\n", address(yieldPassImpl));

        /* YieldPass Upgradeable Beacon */
        console.log("Deploying YieldPass proxy...");

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(yieldPassImpl), msg.sender, abi.encodeWithSignature("initialize()"));

        /* Log deployment */
        _deployment.yieldPass = address(proxy);

        console.log("YieldPass proxy deployed at: %s\n", address(proxy));

        return address(proxy);
    }
}
