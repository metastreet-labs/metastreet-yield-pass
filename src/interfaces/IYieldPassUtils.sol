// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Interface to Yield Pass Utilities
 * @author MetaStreet Foundation
 */
interface IYieldPassUtils {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address (e.g. zero address)
     */
    error InvalidAddress();

    /**
     * @notice Invalid slippage
     */
    error InvalidSlippage();

    /**
     * @notice Deadline passed
     */
    error DeadlinePassed();

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Quote balanced LP
     * @param yieldPassToken Yield pass token
     * @param currencyToken Currency token
     * @param yieldPassAmount Yield pass amount
     * @return Currency token amount
     */
    function quoteBalancedLP(
        address yieldPassToken,
        address currencyToken,
        uint256 yieldPassAmount
    ) external view returns (uint256);

    /**
     * @notice Validate balanced LP
     * @param yieldPassToken Yield pass token
     * @param currencyToken Currency token
     * @param yieldPassAmount Yield pass amount
     * @param minCurrencyAmount Minimum currency token amount
     * @param deadline Deadline
     */
    function validateBalancedLP(
        address yieldPassToken,
        address currencyToken,
        uint256 yieldPassAmount,
        uint256 minCurrencyAmount,
        uint64 deadline
    ) external view;
}
