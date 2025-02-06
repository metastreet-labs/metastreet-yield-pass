// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TestYieldToken} from "src/yieldAdapters/test/TestYieldToken.sol";
import {TestNodeLicense} from "src/yieldAdapters/test/TestNodeLicense.sol";
import {TestYieldAdapter} from "src/yieldAdapters/test/TestYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract DeployTestYieldAdapter is Deployer {
    function run(
        uint64 yieldPassExpiry
    ) public broadcast useDeployment returns (address) {
        if (_deployment.yieldPass == address(0)) revert MissingDependency();

        /* Deploy test node license */
        console.log("Deploying TestNodeLicense...");
        TestNodeLicense testNodeLicense = new TestNodeLicense("Test Node License", "TEST-NODE");
        console.log("TestNodeLicense deployed at: %s\n", address(testNodeLicense));

        /* Deploy test yield token */
        console.log("Deploying TestYieldToken...");
        TestYieldToken testYieldToken = new TestYieldToken("Test Yield Token", "TEST");
        console.log("TestYieldToken deployed at: %s\n", address(testYieldToken));

        /* TestYieldAdapter Implementation */
        console.log("Deploying TestYieldAdapter implementation...");
        TestYieldAdapter yieldAdapterImpl = new TestYieldAdapter(
            _deployment.yieldPass, yieldPassExpiry, address(testNodeLicense), address(testYieldToken)
        );
        console.log("TestYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        /* TestYieldAdapter Proxy */
        console.log("Deploying TestYieldAdapter proxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(yieldAdapterImpl), msg.sender, abi.encodeWithSignature("initialize()")
        );
        console.log("TestYieldAdapter proxy deployed at: %s\n", address(proxy));

        /* Grant MINT_ROLE to TestYieldAdapter */
        testYieldToken.grantRole(0x154c00819833dac601ee5ddded6fda79d9d8b506b911b3dbd54cdb95fe6c3686, address(proxy));

        return address(proxy);
    }
}
