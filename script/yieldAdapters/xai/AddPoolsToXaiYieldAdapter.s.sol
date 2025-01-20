// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract AddPoolsToXaiYieldAdapter is Deployer {
    function run(address xaiYieldAdapter, address[] memory pools) public broadcast {
        if (pools.length == 0) revert InvalidParameter();

        for (uint256 i; i < pools.length; i++) {
            if (pools[i] == address(0)) revert InvalidParameter();
        }

        /* Adding pools */
        console.log("Adding pools to XaiYieldAdapter...");

        XaiYieldAdapter(xaiYieldAdapter).addPools(pools);

        console.log("Pools added to XaiYieldAdapter");
    }
}
