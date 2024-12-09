// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libraries/UniswapV2Library.sol";

import {IYieldPassUtils} from "./interfaces/IYieldPassUtils.sol";

/**
 * @title Yield Pass Utilities
 * @author MetaStreet Foundation
 */
contract YieldPassUtils is IYieldPassUtils {
    using UniswapV2Library for *;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Uniswap V2 factory
     */
    address public immutable uniswapV2Factory;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    constructor(
        address uniswapV2Factory_
    ) {
        require(address(uniswapV2Factory_) != address(0), "Invalid address");

        uniswapV2Factory = uniswapV2Factory_;
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Compute balanced LP
     * @param yieldPassToken Yield pass token
     * @param currencyToken Currency token
     * @param yieldPassAmount Yield pass amount
     * @return Currency token amount
     */
    function _computeBalancedLP(
        address yieldPassToken,
        address currencyToken,
        uint256 yieldPassAmount
    ) internal view returns (uint256) {
        /* Get Uniswap V2 pair reserves */
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(uniswapV2Factory, yieldPassToken, currencyToken);

        /* Return computed currency token amount */
        return Math.mulDiv(yieldPassAmount, reserveB, reserveA);
    }

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPassUtils
     */
    function quoteBalancedLP(
        address yieldPassToken,
        address currencyToken,
        uint256 yieldPassAmount
    ) external view returns (uint256) {
        return _computeBalancedLP(yieldPassToken, currencyToken, yieldPassAmount);
    }

    /**
     * @inheritdoc IYieldPassUtils
     */
    function validateBalancedLP(
        address yieldPassToken,
        address currencyToken,
        uint256 yieldPassAmount,
        uint256 minCurrencyAmount,
        uint64 deadline
    ) external view {
        /* Compute balanced LP amount */
        uint256 currencyAmount = _computeBalancedLP(yieldPassToken, currencyToken, yieldPassAmount);

        /* Validate min currency amount */
        if (currencyAmount < minCurrencyAmount) revert InvalidSlippage();

        /* Validate deadline */
        if (block.timestamp > deadline) revert DeadlinePassed();
    }
}
