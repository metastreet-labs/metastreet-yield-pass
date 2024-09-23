// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract Show is Deployer {
    function run() public {
        console.log("Printing deployments\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        /* Deserialize */
        _deserialize();

        console.log("Yield Pass:       %s", _deployment.yieldPass);
        // console.log("Yield Pass Utils: %s", _deployment.yieldPassUtils);

        console.log("Printing deployments completed");
    }
}
