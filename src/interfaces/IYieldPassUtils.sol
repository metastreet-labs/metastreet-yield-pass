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

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when token is liquidated
     * @param liquidator Liquidator address
     * @param token Token
     * @param tokenId Token ID
     * @param yieldPassAmount Yield pass amount
     * @param principal Principal
     */
    event TokenLiquidated(
        address indexed liquidator,
        address indexed token,
        uint256 indexed tokenId,
        uint256 yieldPassAmount,
        uint256 principal
    );

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Liquidate NFTs
     * @param yieldPass Yield pass
     * @param tokenIds Token IDs
     * @param setupData Setup data
     * @param pool Pool
     * @param duration Duration
     * @param maxRepayment Maximum repayment
     * @param ticks Ticks
     * @param options Options
     * @param minLiquidityTokens Minimum liquidity tokens
     */
    function liquidateToken(
        address yieldPass,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint256 minLiquidityTokens
    ) external;
}
