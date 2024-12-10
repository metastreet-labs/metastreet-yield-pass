// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AethirYieldAdapter} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract DeployAethirYieldAdapter is Deployer {
    function run(
        address checkerNodeLicense,
        address checkerClaimAndWithdraw,
        uint48 cliffSeconds,
        address signer
    ) public broadcast useDeployment returns (address) {
        if (_deployment.yieldPass == address(0)) revert MissingDependency();

        /* AethirYieldAdapter Implementation */
        console.log("Deploying AethirYieldAdapter implementation...");

        AethirYieldAdapter yieldAdapterImpl =
            new AethirYieldAdapter(_deployment.yieldPass, checkerNodeLicense, checkerClaimAndWithdraw);

        console.log("AethirYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        /* AethirYieldAdapter Proxy */
        console.log("Deploying AethirYieldAdapter proxy...");

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(yieldAdapterImpl),
            msg.sender,
            abi.encodeWithSignature("initialize(uint48,address)", cliffSeconds, signer)
        );

        console.log("AethirYieldAdapter proxy deployed at: %s\n", address(proxy));

        return address(proxy);
    }
}
