// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {YieldPassUtils} from "src/YieldPassUtils.sol";
import {Deployer} from "script/utils/Deployer.s.sol";

contract DeployYieldPassUtils is Deployer {
    function run(
        address uniswapV2SwapRouter,
        address yieldPass,
        address bundleCollateralWrapper
    ) public broadcast useDeployment returns (address) {
        if (_deployment.yieldPassUtils != address(0)) revert AlreadyDeployed();

        /* YieldPassUtils Implementation */
        console.log("Deploying YieldPassUtils implementation...");

        YieldPassUtils yieldPassUtilsImpl =
            new YieldPassUtils(IUniswapV2Router02(uniswapV2SwapRouter), IYieldPass(yieldPass), bundleCollateralWrapper);

        console.log("YieldPassUtils implementation deployed at: %s\n", address(yieldPassUtilsImpl));

        /* YieldPassUtils Upgradeable Beacon */
        console.log("Deploying YieldPassUtils proxy...");

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(yieldPassUtilsImpl), msg.sender, abi.encodeWithSignature("initialize()")
        );

        /* Log deployment */
        _deployment.yieldPassUtils = address(proxy);

        console.log("YieldPassUtils proxy deployed at: %s\n", address(proxy));

        return address(proxy);
    }
}
