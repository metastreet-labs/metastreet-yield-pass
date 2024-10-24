// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

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
    /* Implementation */
    /*------------------------------------------------------------------------*/

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
        uint256 minLiquidityTokens
    ) external nonReentrant {
        /* Get yield pass info */
        IYieldPass.YieldPassInfo memory yieldPassInfo = yieldPass.yieldPassInfo(yieldPassToken);

        /* Approve NFT with yield pass contract */
        IERC721(yieldPassInfo.token).setApprovalForAll(address(yieldPass), true);

        /* Transfer NFTs and mint yield pass tokens */
        uint256 yieldPassAmount;
        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer NFT from seller to this contract */
            IERC721(yieldPassInfo.token).transferFrom(msg.sender, address(this), tokenIds[i]);

            /* Mint yield pass token and discount pass token */
            yieldPassAmount +=
                yieldPass.mint(yieldPassInfo.token, tokenIds[i], address(this), address(this), setupData[i]);
        }

        /* Unset NFT approval for yield pass contract */
        IERC721(yieldPassInfo.token).setApprovalForAll(address(yieldPass), false);

        /* Get pool currency token */
        address poolCurrencyToken = IPool(pool).currencyToken();

        /* Get Uniswap V2 pair reserves */
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(uniswapV2Factory, yieldPassToken, poolCurrencyToken);

        /* Compute borrow principal */
        uint256 principal = Math.mulDiv(yieldPassAmount, reserveB, reserveA);

        /* Borrow from pool using discount pass */
        if (tokenIds.length == 1) {
            /* Approve discount pass token for pool */
            IERC721(yieldPassInfo.discountPass).approve(address(pool), tokenIds[0]);

            /* Borrow using discount pass */
            IPool(pool).borrow(
                principal, duration, yieldPassInfo.discountPass, tokenIds[0], maxRepayment, ticks, options
            );
        } else {
            /* Mint bundle collateral wrapper */
            uint256 tokenId =
                IBundleCollateralWrapper(bundleCollateralWrapper).mint(yieldPassInfo.discountPass, tokenIds);

            /* Approve bundle collateral wrapper for pool */
            IERC721(bundleCollateralWrapper).approve(address(pool), tokenId);

            /* Borrow */
            IPool(pool).borrow(principal, duration, bundleCollateralWrapper, tokenId, maxRepayment, ticks, options);
        }

        /* Approve pool currency token and yield pass token for Uniswap V2 router */
        IERC20(poolCurrencyToken).approve(address(uniswapV2SwapRouter), principal);
        IERC20(yieldPassToken).approve(address(uniswapV2SwapRouter), yieldPassAmount);

        /* Add liquidity */
        (,, uint256 liquidityTokens) = uniswapV2SwapRouter.addLiquidity(
            yieldPassToken, poolCurrencyToken, yieldPassAmount, principal, 1, 1, msg.sender, block.timestamp
        );

        /* Validate slippage */
        if (liquidityTokens < minLiquidityTokens) revert InvalidSlippage();

        /* Emit token liquidated event */
        uint256 avgYieldPassAmount = yieldPassAmount / tokenIds.length;
        uint256 avgPrincipal = principal / tokenIds.length;
        for (uint256 i; i < tokenIds.length; i++) {
            emit TokenLiquidated(msg.sender, yieldPassInfo.token, tokenIds[i], avgYieldPassAmount, avgPrincipal);
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
