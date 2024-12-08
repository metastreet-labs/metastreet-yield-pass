// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {Deployer} from "script/utils/Deployer.s.sol";

contract YieldPassCreate is Deployer {
    function run(
        address nft,
        uint64 startTime,
        uint64 expiry,
        bool isUserLocked,
        address adapter
    ) public broadcast useDeployment returns (address, address) {
        IYieldPass yieldPass = IYieldPass(_deployment.yieldPass);

        console.log("Creating Yield Pass Token...");

        (address yieldPassToken, address nodePassToken) =
            yieldPass.deployYieldPass(nft, startTime, expiry, isUserLocked, adapter);

        console.log("Yield Pass Token: %s\n", yieldPassToken);
        console.log("Node Pass Token: %s\n", nodePassToken);

        return (yieldPassToken, nodePassToken);
    }
}
