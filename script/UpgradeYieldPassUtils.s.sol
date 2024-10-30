// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {YieldPassUtils} from "src/YieldPassUtils.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeYieldPassUtils is Deployer {
    function run(
        address uniswapV2SwapRouter,
        address yieldPass,
        address bundleCollateralWrapper
    ) public broadcast useDeployment returns (address) {
        /* Deploy new YieldPassUtils Implementation */
        console.log("Deploying YieldPassUtils implementation...");

        YieldPassUtils yieldPassUtilsImpl =
            new YieldPassUtils(IUniswapV2Router02(uniswapV2SwapRouter), IYieldPass(yieldPass), bundleCollateralWrapper);

        console.log("YieldPassUtils implementation deployed at: %s\n", address(yieldPassUtilsImpl));

        console.log("Upgrading proxy %s implementation...", _deployment.yieldPassUtils);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.yieldPassUtils, ERC1967Utils.ADMIN_SLOT))));

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(_deployment.yieldPassUtils), address(yieldPassUtilsImpl), ""
        );

        console.log(
            "Upgraded proxy %s implementation to: %s\n", _deployment.yieldPassUtils, address(yieldPassUtilsImpl)
        );

        return address(yieldPassUtilsImpl);
    }
}
