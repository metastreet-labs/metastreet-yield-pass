// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title Abridged interface to Reservoir V6 router
 */
interface IReservoirV6_0_1 {
    struct ExecutionInfo {
        address module;
        bytes data;
        uint256 value;
    }

    function execute(
        ExecutionInfo[] calldata executionInfos
    ) external payable;
}
