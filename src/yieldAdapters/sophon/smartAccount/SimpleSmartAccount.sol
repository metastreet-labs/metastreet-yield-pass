// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title Sophon Smart Account
 * @author MetaStreet Foundation
 * @notice A simple smart contract wallet that can execute transactions on behalf of its owner
 * @dev This contract allows the owner to execute single or batched transactions
 */
contract SimpleSmartAccount {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice A call to execute
     */
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice The owner of this smart wallet
     */
    address public immutable owner;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructs a new smart wallet
     * @param _owner The address that will own and control this wallet
     */
    constructor(
        address _owner
    ) {
        owner = _owner;
    }

    /*------------------------------------------------------------------------*/
    /* Internal Functions */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Internal function to execute a transaction
     * @param target The address of the contract to interact with
     * @param value The amount of ETH to send
     * @param data The calldata to execute
     */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Restricts function access to the wallet owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Public Functions */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Executes a single transaction
     * @param target The address of the contract to interact with
     * @param value The amount of ETH to send
     * @param data The calldata to execute
     */
    function execute(address target, uint256 value, bytes calldata data) external payable onlyOwner {
        _call(target, value, data);
    }

    /**
     * @notice Executes multiple transactions in a single call
     * @param calls Array of transactions to execute
     */
    function executeBatch(
        Call[] calldata calls
    ) external payable onlyOwner {
        for (uint256 i; i < calls.length; i++) {
            _call(calls[i].target, calls[i].value, calls[i].data);
        }
    }
}
