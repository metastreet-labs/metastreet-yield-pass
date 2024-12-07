// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IYieldPassUtils.sol";

import "./libraries/UniswapV2Library.sol";

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
        if (address(uniswapV2Factory_) == address(0)) revert InvalidAddress();

        uniswapV2Factory = uniswapV2Factory_;
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get borrow principal
     * @param yieldPassToken Yield pass token
     * @param poolCurrencyToken Pool currency token
     * @param yieldPassAmount Yield pass amount
     * @return Borrow principal
     */
    function _computeBorrowPrincipal(
        address yieldPassToken,
        address poolCurrencyToken,
        uint256 yieldPassAmount
    ) internal view returns (uint256) {
        /* Get Uniswap V2 pair reserves */
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(uniswapV2Factory, yieldPassToken, poolCurrencyToken);

        /* Return computed borrow principal */
        return Math.mulDiv(yieldPassAmount, reserveB, reserveA);
    }

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPassUtils
     */
    function quoteBorrowPrincipal(
        address yieldPassToken,
        address poolCurrencyToken,
        uint256 yieldPassAmount
    ) external view returns (uint256) {
        return _computeBorrowPrincipal(yieldPassToken, poolCurrencyToken, yieldPassAmount);
    }

    /**
     * @inheritdoc IYieldPassUtils
     */
    function validateBorrow(
        address yieldPassToken,
        address poolCurrencyToken,
        uint256 yieldPassAmount,
        uint256 minPrincipal,
        uint64 deadline
    ) external view {
        /* Compute borrow principal */
        uint256 principal = _computeBorrowPrincipal(yieldPassToken, poolCurrencyToken, yieldPassAmount);

        /* Validate min principal */
        if (principal < minPrincipal) revert InvalidSlippage();

        /* Validate deadline */
        if (block.timestamp > deadline) revert DeadlinePassed();
    }
}
