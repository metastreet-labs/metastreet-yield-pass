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
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted after minting and borrowing
     * @param liquidator Liquidator address
     * @param token Token
     * @param tokenId Token ID
     * @param yieldPassAmount Yield pass amount
     * @param principal Principal
     */
    event Liquidated(
        address indexed liquidator,
        address indexed token,
        uint256 indexed tokenId,
        uint256 yieldPassAmount,
        uint256 principal
    );

    /**
     * @notice Emitted after minting, borrowing, and adding liquidity
     * @param liquidator Liquidator address
     * @param token Token
     * @param tokenId Token ID
     * @param yieldPassAmount Yield pass amount
     * @param principal Principal
     * @param liquidityTokens Liquidity tokens
     */
    event Liquidated(
        address indexed liquidator,
        address indexed token,
        uint256 indexed tokenId,
        uint256 yieldPassAmount,
        uint256 principal,
        uint256 liquidityTokens
    );

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Liquidate NFT partially
     * @param yieldPass Yield pass
     * @param tokenIds Token IDs
     * @param setupData Setup data
     * @param pool Pool
     * @param principal Principal
     * @param duration Duration
     * @param maxRepayment Maximum repayment
     * @param ticks Ticks
     * @param options Options
     * @param deadline Deadline for mint
     * @return Repayment amount
     */
    function mintAndBorrow(
        address yieldPass,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint256 principal,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint64 deadline
    ) external returns (uint256);

    /**
     * @notice Quote yield pass amount minted and borrow principal
     * @param yieldPassToken Yield pass token
     * @param pool Pool
     * @param tokenCount Token count
     * @return Yield pass amount and computed borrow principal
     */
    function quoteMintAndLP(
        address yieldPassToken,
        address pool,
        uint256 tokenCount
    ) external view returns (uint256, uint256);

    /**
     * @notice Liquidate NFT
     * @param yieldPass Yield pass
     * @param tokenIds Token IDs
     * @param setupData Setup data
     * @param pool Pool
     * @param minPrincipal Minimum borrow principal
     * @param duration Duration
     * @param maxRepayment Maximum repayment
     * @param ticks Ticks
     * @param options Options
     * @param deadline Deadline for mint
     * @return Repayment amount and liquidity tokens
     */
    function mintAndLP(
        address yieldPass,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint256 minPrincipal,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint64 deadline
    ) external returns (uint256, uint256);
}
