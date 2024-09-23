// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {Deployer} from "script/utils/Deployer.s.sol";

contract YieldPassSetYieldAdapter is Deployer {
    function run(address yieldPass_, address yieldAdapter) public broadcast useDeployment {
        IYieldPass yieldPass = IYieldPass(_deployment.yieldPass);

        console.log("Setting Yield Adapter...");

        yieldPass.setYieldAdapter(yieldPass_, yieldAdapter);
    }
}
