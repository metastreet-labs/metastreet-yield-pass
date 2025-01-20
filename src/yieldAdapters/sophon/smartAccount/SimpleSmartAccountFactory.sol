// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./SimpleSmartAccount.sol";

import {console} from "forge-std/console.sol";

interface ISimpleSmartAccount {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function execute(address target, uint256 value, bytes calldata data) external payable;
    function executeBatch(
        Call[] calldata calls
    ) external payable;
}

/**
 * @title Simple Smart Account Factory
 * @author MetaStreet Foundation
 */
contract SimpleSmartAccountFactory {
    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mapping from owner to smart account
     */
    mapping(address => address) public smartAccounts;

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when a new smart account is created
     */
    event SmartAccountCreated(address indexed owner, address indexed account);

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor for the simple smart account factory
     */
    constructor() {}

    /*------------------------------------------------------------------------*/
    /* Public Functions */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Creates a new Simple smart account
     * @return account The address of the newly created smart account
     */
    function createAccount() external returns (ISimpleSmartAccount) {
        /* Validate that the caller has not already created a smart account */
        if (smartAccounts[msg.sender] != address(0)) return ISimpleSmartAccount(smartAccounts[msg.sender]);

        /* Create the smart account */
        address account = address(new SimpleSmartAccount(msg.sender));

        /* Store the smart account */
        smartAccounts[msg.sender] = account;

        /* Emit the event */
        emit SmartAccountCreated(msg.sender, account);

        return ISimpleSmartAccount(account);
    }

    /**
     * @notice Get the address of the smart account for an owner
     * @param owner The address owns the smart account
     * @return The address of the smart account
     */
    function getAddress(
        address owner
    ) external view returns (address) {
        return smartAccounts[owner];
    }
}
