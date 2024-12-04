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
     * @notice Validate borrow principal
     * @param yieldPassToken Yield pass token
     * @param poolToken Pool token
     * @param yieldPassAmount Yield pass amount
     * @param minPrincipal Minimum principal
     * @param deadline Deadline
     */
    function validateBorrow(
        address yieldPassToken,
        address poolToken,
        uint256 yieldPassAmount,
        uint256 minPrincipal,
        uint64 deadline
    ) external view;

    /**
     * @notice Quote borrow principal
     * @param yieldPassToken Yield pass token
     * @param poolToken Pool token
     * @param yieldPassAmount Yield pass amount
     * @return Borrow principal
     */
    function quoteBorrowPrincipal(
        address yieldPassToken,
        address poolToken,
        uint256 yieldPassAmount
    ) external view returns (uint256);
}
