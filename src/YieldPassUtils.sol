// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "metastreet-contracts-v2/interfaces/IPool.sol";

import "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

import "./interfaces/IYieldPassUtils.sol";
import "./interfaces/IYieldPass.sol";

import "./libraries/UniswapV2Library.sol";

interface IBundleCollateralWrapper {
    function mint(address token, uint256[] calldata tokenIds) external returns (uint256);
}

/**
 * @title Yield Pass Utilities
 * @author MetaStreet Foundation
 */
contract YieldPassUtils is ReentrancyGuard, ERC721Holder, ERC165, IYieldPassUtils {
    using SafeERC20 for IERC20;
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

    /**
     * @notice Uniswap V2 swap router
     */
    IUniswapV2Router02 public immutable uniswapV2SwapRouter;

    /**
     * @notice Yield pass
     */
    IYieldPass public immutable yieldPass;

    /**
     * @notice Bundle collateral wrapper
     */
    address public immutable bundleCollateralWrapper;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    constructor(IUniswapV2Router02 uniswapV2SwapRouter_, IYieldPass yieldPass_, address bundleCollateralWrapper_) {
        if (address(uniswapV2SwapRouter_) == address(0)) revert InvalidAddress();
        if (address(yieldPass_) == address(0)) revert InvalidAddress();
        if (address(bundleCollateralWrapper_) == address(0)) revert InvalidAddress();

        uniswapV2Factory = uniswapV2SwapRouter_.factory();
        uniswapV2SwapRouter = uniswapV2SwapRouter_;
        yieldPass = yieldPass_;
        bundleCollateralWrapper = bundleCollateralWrapper_;
    }

    /*------------------------------------------------------------------------*/
    /* Helper */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper function to mint yield pass tokens and borrow from pool
     * @param yieldPassToken Yield pass token
     * @param tokenIds Token IDs
     * @param setupData Setup data
     * @param pool Pool
     * @param principal Principal
     * @param duration Duration
     * @param maxRepayment Max repayment
     * @param ticks Ticks
     * @param options Options
     * @param deadline Deadline
     * @param isLP True if adding liquidity to Uniswap V2 pool
     * @return Token, pool currency token, yield pass amount, principal
     */
    function _mintAndBorrow(
        address yieldPassToken,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint256 principal,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint64 deadline,
        bool isLP
    ) internal returns (address, address, uint256, uint256) {
        /* Validate deadline */
        if (block.timestamp > deadline) revert DeadlinePassed();

        /* Get yield pass info */
        IYieldPass.YieldPassInfo memory yieldPassInfo = yieldPass.yieldPassInfo(yieldPassToken);

        /* Get pool currency token */
        address poolCurrencyToken = IPool(pool).currencyToken();

        /* Approve NFT with yield pass contract */
        IERC721(yieldPassInfo.token).setApprovalForAll(address(yieldPass), true);

        /* Transfer NFTs and mint yield pass tokens */
        uint256 yieldPassAmount;
        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer NFT from liquidator to this contract */
            IERC721(yieldPassInfo.token).safeTransferFrom(msg.sender, address(this), tokenIds[i]);

            /* Mint yield pass token and discount pass token */
            yieldPassAmount += yieldPass.mint(yieldPassToken, tokenIds[i], address(this), address(this), setupData[i]);
        }

        /* Unset NFT approval for yield pass contract */
        IERC721(yieldPassInfo.token).setApprovalForAll(address(yieldPass), false);

        /* If adding liquidity, compute borrow principal */
        if (isLP) {
            /* Get Uniswap V2 pair reserves */
            (uint256 reserveA, uint256 reserveB) =
                UniswapV2Library.getReserves(uniswapV2Factory, yieldPassToken, poolCurrencyToken);

            /* Compute borrow principal */
            principal = Math.mulDiv(yieldPassAmount, reserveB, reserveA);
        }

        /* Borrow from pool using discount pass */
        if (tokenIds.length == 1) {
            /* Approve discount pass token for pool */
            IERC721(yieldPassInfo.discountPass).approve(pool, tokenIds[0]);

            /* Borrow using discount pass */
            IPool(pool).borrow(
                principal, duration, yieldPassInfo.discountPass, tokenIds[0], maxRepayment, ticks, options
            );
        } else {
            /* Approve discount pass token for bundle collateral wrapper */
            IERC721(yieldPassInfo.discountPass).setApprovalForAll(bundleCollateralWrapper, true);

            /* Mint bundle collateral wrapper */
            uint256 tokenId =
                IBundleCollateralWrapper(bundleCollateralWrapper).mint(yieldPassInfo.discountPass, tokenIds);

            /* Approve discount pass token for bundle collateral wrapper */
            IERC721(yieldPassInfo.discountPass).setApprovalForAll(bundleCollateralWrapper, false);

            /* Approve bundle collateral wrapper for pool */
            IERC721(bundleCollateralWrapper).approve(pool, tokenId);

            /* Borrow */
            IPool(pool).borrow(principal, duration, bundleCollateralWrapper, tokenId, maxRepayment, ticks, options);
        }

        return (yieldPassInfo.token, poolCurrencyToken, yieldPassAmount, principal);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPassUtils
     */
    function quoteLiquidateToken(
        address yieldPassToken,
        address pool,
        uint256 tokenCount
    ) external view returns (uint256, uint256) {
        /* Get pool currency token */
        address poolCurrencyToken = IPool(pool).currencyToken();

        /* Get yield pass amount */
        uint256 yieldPassAmount = yieldPass.quoteMint(yieldPassToken) * tokenCount;

        /* Get Uniswap V2 pair reserves */
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(uniswapV2Factory, yieldPassToken, poolCurrencyToken);

        /* Return yield pass amount and computed borrow principal */
        return (yieldPassAmount, Math.mulDiv(yieldPassAmount, reserveB, reserveA));
    }

    /*------------------------------------------------------------------------*/
    /* Implementation */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPassUtils
     */
    function liquidateTokenPartial(
        address yieldPassToken,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint256 principal,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint64 deadline
    ) external nonReentrant {
        /* Mint and borrow */
        (address token, address poolCurrencyToken, uint256 yieldPassAmount,) = _mintAndBorrow(
            yieldPassToken,
            tokenIds,
            setupData,
            pool,
            principal,
            duration,
            maxRepayment,
            ticks,
            options,
            deadline,
            false
        );

        /* Send principal and yield pass amount to caller */
        IERC20(poolCurrencyToken).safeTransfer(msg.sender, principal);
        IERC20(yieldPassToken).safeTransfer(msg.sender, yieldPassAmount);

        /* Emit token partially liquidated event */
        uint256 avgYieldPassAmount = yieldPassAmount / tokenIds.length;
        uint256 avgPrincipal = principal / tokenIds.length;
        for (uint256 i; i < tokenIds.length; i++) {
            emit TokenLiquidatedPartial(msg.sender, token, tokenIds[i], avgYieldPassAmount, avgPrincipal);
        }
    }

    /**
     * @inheritdoc IYieldPassUtils
     */
    function liquidateToken(
        address yieldPassToken,
        uint256[] calldata tokenIds,
        bytes[] calldata setupData,
        address pool,
        uint64 duration,
        uint256 maxRepayment,
        uint128[] calldata ticks,
        bytes calldata options,
        uint256 minPrincipal,
        uint64 deadline
    ) external nonReentrant {
        /* Mint and borrow */
        (address token, address poolCurrencyToken, uint256 yieldPassAmount, uint256 principal) = _mintAndBorrow(
            yieldPassToken, tokenIds, setupData, pool, 0, duration, maxRepayment, ticks, options, deadline, true
        );

        /* Validate min principal */
        if (principal < minPrincipal) revert InvalidSlippage();

        /* Approve pool currency token and yield pass token for Uniswap V2 router */
        IERC20(poolCurrencyToken).approve(address(uniswapV2SwapRouter), principal);
        IERC20(yieldPassToken).approve(address(uniswapV2SwapRouter), yieldPassAmount);

        /* Add liquidity */
        (,, uint256 liquidityTokens) = uniswapV2SwapRouter.addLiquidity(
            yieldPassToken, poolCurrencyToken, yieldPassAmount, principal, 1, 1, msg.sender, block.timestamp
        );

        /* Emit token liquidated event */
        uint256 avgYieldPassAmount = yieldPassAmount / tokenIds.length;
        uint256 avgPrincipal = principal / tokenIds.length;
        uint256 avgLiquidityTokens = liquidityTokens / tokenIds.length;
        for (uint256 i; i < tokenIds.length; i++) {
            emit TokenLiquidated(msg.sender, token, tokenIds[i], avgYieldPassAmount, avgPrincipal, avgLiquidityTokens);
        }
    }

    /*------------------------------------------------------------------------*/
    /* ERC165 interface */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
