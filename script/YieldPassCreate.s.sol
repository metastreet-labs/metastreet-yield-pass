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
        bool isTransferable,
        address adapter
    ) public broadcast useDeployment returns (address, address) {
        IYieldPass yieldPass = IYieldPass(_deployment.yieldPass);

        console.log("Creating Yield Pass Token...");

        (address yieldToken, address discountToken) =
            yieldPass.deployYieldPass(nft, startTime, expiry, isTransferable, adapter);

        console.log("Yield Token: %s\n", yieldToken);
        console.log("Discount Token: %s\n", discountToken);

        return (yieldToken, discountToken);
    }
}
