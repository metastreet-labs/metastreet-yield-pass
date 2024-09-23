// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Interface to Wrapped Ether Token Contract
 */
interface IWETH is IERC20 {
    /**
     * @notice Deposit Ether for ERC20 Wrapped Ether
     */
    function deposit() external payable;

    /**
     * @notice Withdraw ERC20 Wrapped Ether for Ether
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;
}
