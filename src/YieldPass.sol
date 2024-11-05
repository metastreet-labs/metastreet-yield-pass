// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {IYieldPass} from "./interfaces/IYieldPass.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {YieldPassToken} from "./YieldPassToken.sol";
import {DiscountPassToken} from "./DiscountPassToken.sol";

/**
 * @title Yield Pass
 * @author MetaStreet Foundation
 */
contract YieldPass is IYieldPass, ReentrancyGuard, AccessControl, Multicall, ERC721Holder {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass state
     * @param yieldAdapter Yield adapter
     * @param tokenIds Array of token IDs
     * @param claimState Claim status
     * @param tokenIdRedemptions Map of token ID to redemption address
     */
    struct YieldPassState {
        IYieldAdapter yieldAdapter;
        YieldClaimState claimState;
        mapping(uint256 => address) tokenIdRedemptions;
    }

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Array of yield pass tokens
     */
    address[] internal _yieldPasses;

    /**
     * @notice Map of yield pass to yield pass info
     */
    mapping(address => YieldPassInfo) internal _yieldPassInfos;

    /**
     * @notice Map of yield pass to yield pass state
     */
    mapping(address => YieldPassState) internal _yieldPassStates;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldPass constructor
     */
    constructor() {
        _initialized = true;
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldPass initializer
     */
    function initialize() external {
        require(!_initialized, "Already initialized");

        _initialized = true;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPass
     */
    function yieldPassInfo(address yieldPass) public view returns (YieldPassInfo memory) {
        return _yieldPassInfos[yieldPass];
    }

    /**
     * @inheritdoc IYieldPass
     */
    function yieldPassInfos(uint256 offset, uint256 count) public view returns (YieldPassInfo[] memory) {
        /* Clamp on count */
        count = Math.min(count, _yieldPasses.length - offset);

        /* Create arrays */
        YieldPassInfo[] memory yieldPassInfos_ = new YieldPassInfo[](count);

        /* Fill array */
        for (uint256 i = offset; i < offset + count; i++) {
            yieldPassInfos_[i - offset] = yieldPassInfo(_yieldPasses[i]);
        }

        return yieldPassInfos_;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claimState(address yieldPass) public view returns (YieldClaimState memory) {
        return _yieldPassStates[yieldPass].claimState;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function yieldAdapter(address yieldPass) public view returns (address) {
        return address(_yieldPassStates[yieldPass].yieldAdapter);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function cumulativeYield(address yieldPass) public view returns (uint256) {
        return _yieldPassStates[yieldPass].yieldAdapter.cumulativeYield();
    }

    /**
     * @inheritdoc IYieldPass
     */
    function cumulativeYield(address yieldPass, uint256 yieldPassAmount) public view returns (uint256) {
        return Math.mulDiv(
            _yieldPassStates[yieldPass].yieldAdapter.cumulativeYield(),
            yieldPassAmount,
            _yieldPassStates[yieldPass].claimState.shares
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claimable(address yieldPass, uint256 yieldPassAmount) public view returns (uint256) {
        return Math.mulDiv(
            _yieldPassStates[yieldPass].claimState.total, yieldPassAmount, _yieldPassStates[yieldPass].claimState.shares
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function quoteMint(address yieldPass) public view returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Validate yield pass is deployed */
        if (yieldPassInfo_.expiry == 0) revert InvalidYieldPass();

        /* Validate mint window is open */
        if (block.timestamp < yieldPassInfo_.startTime || block.timestamp >= yieldPassInfo_.expiry) {
            revert InvalidWindow();
        }

        /* Comptue yield pass token amount based on this yield pass's time to expiry */
        return
            (1 ether * (yieldPassInfo_.expiry - block.timestamp)) / (yieldPassInfo_.expiry - yieldPassInfo_.startTime);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper to get deployment hash
     * @param token Token address
     * @param expiry Expiry
     * @return Deployment hash
     */
    function _getDeploymentHash(address token, uint256 expiry) internal pure returns (bytes32) {
        /* Compute deployment hash based on token, and expiry */
        return keccak256(abi.encodePacked(token, expiry));
    }

    /**
     * @notice Helper to get constructor parameters for token deployment
     * @param isYieldPass True if constructing parameters for yield pass token
     * @param token Token address
     * @param expiry Expiry
     * @param isTransferable True if token is transferable
     * @return Encoded constructor parameters
     */
    function _getCtorParam(
        bool isYieldPass,
        address token,
        uint256 expiry,
        bool isTransferable
    ) internal view returns (bytes memory) {
        /* Get token metadata */
        IERC721Metadata metadata = IERC721Metadata(token);
        string memory name = metadata.name();
        string memory symbol = metadata.symbol();

        /* Configure token constructor params */
        string memory tokenName = string.concat(
            name, " (", isYieldPass ? "Yield" : "Discount", " Pass - Expiry: ", Strings.toString(expiry), ")"
        );
        string memory tokenSymbol = string.concat(symbol, "-", isYieldPass ? "YP" : "DP", "-", Strings.toString(expiry));

        return isYieldPass ? abi.encode(tokenName, tokenSymbol) : abi.encode(tokenName, tokenSymbol, isTransferable);
    }

    /**
     * @notice Helper to harvest yield from yield adapter
     * @param yieldPass Yield pass token
     * @param harvestData Harvest data
     * @return Amount harvested
     */
    function _harvest(address yieldPass, bytes calldata harvestData) internal returns (uint256) {
        /* Validate yield pass is deployed */
        if (_yieldPassInfos[yieldPass].expiry == 0) revert InvalidYieldPass();

        IYieldAdapter yieldAdapter_ = _yieldPassStates[yieldPass].yieldAdapter;

        /* Admin update yield adapter */
        uint256 amount = yieldAdapter_.harvest(_yieldPassInfos[yieldPass].expiry, harvestData);

        _yieldPassStates[yieldPass].claimState.balance += amount;
        _yieldPassStates[yieldPass].claimState.total += amount;

        /* Emit Harvested */
        emit Harvested(yieldPass, amount);

        return amount;
    }

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPass
     */
    function mint(
        address yieldPass,
        uint256 tokenId,
        address yieldPassRecipient,
        address discountPassRecipient,
        bytes calldata setupData
    ) external nonReentrant returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Quote mint amount */
        uint256 yieldPassAmount = quoteMint(yieldPass);

        /* Update claim state shares */
        _yieldPassStates[yieldPass].claimState.shares += yieldPassAmount;

        /* Transfer ERC721 from caller to yield adapter */
        IERC721(yieldPassInfo_.token).safeTransferFrom(
            msg.sender, address(_yieldPassStates[yieldPass].yieldAdapter), tokenId
        );

        /* Call yield adapter setup hook */
        address operator = _yieldPassStates[yieldPass].yieldAdapter.setup(
            tokenId, yieldPassInfo_.expiry, msg.sender, discountPassRecipient, setupData
        );

        /* Mint yield pass token */
        YieldPassToken(yieldPass).mint(yieldPassRecipient, yieldPassAmount);

        /* Mint discount pass token */
        DiscountPassToken(yieldPassInfo_.discountPass).mint(discountPassRecipient, tokenId);

        /* Emit Minted */
        emit Minted(
            msg.sender, yieldPass, yieldPassInfo_.token, yieldPassAmount, yieldPassInfo_.discountPass, tokenId, operator
        );

        return yieldPassAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function harvest(address yieldPass, bytes calldata harvestData) external nonReentrant returns (uint256) {
        return _harvest(yieldPass, harvestData);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claim(address yieldPass, uint256 yieldPassAmount) external nonReentrant returns (uint256) {
        /* Validate yield pass amount */
        if (yieldPassAmount == 0 || YieldPassToken(yieldPass).balanceOf(msg.sender) < yieldPassAmount) {
            revert InvalidAmount();
        }

        /* Validate expiry is in the past */
        if (block.timestamp <= _yieldPassInfos[yieldPass].expiry) revert InvalidWindow();

        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        /* Validate claim with yield adapter */
        if (!yieldPassState.yieldAdapter.validateClaim(msg.sender)) revert InvalidClaim();

        /* Compute yield amount */
        uint256 yieldAmount = claimable(yieldPass, yieldPassAmount);

        /* Update yield claim state */
        yieldPassState.claimState.balance -= yieldAmount;

        /* Burn yield pass amount */
        YieldPassToken(yieldPass).burn(msg.sender, yieldPassAmount);

        /* Get yield token */
        address yieldToken = yieldPassState.yieldAdapter.token();

        /* Transfer yield amount to caller */
        if (yieldAmount > 0) IERC20(yieldToken).safeTransfer(msg.sender, yieldAmount);

        /* Emit Claimed */
        emit Claimed(msg.sender, yieldPass, yieldPassAmount, yieldToken, yieldAmount);

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function redeem(address yieldPass, uint256 tokenId) external nonReentrant returns (bytes memory) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Validate caller owns discount pass */
        if (DiscountPassToken(yieldPassInfo_.discountPass).ownerOf(tokenId) != msg.sender) revert InvalidRedemption();

        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        /* Store redemption address */
        yieldPassState.tokenIdRedemptions[tokenId] = msg.sender;

        /* Call yield adapter initiate teardown hook */
        bytes memory teardownData = yieldPassState.yieldAdapter.initiateTeardown(tokenId, yieldPassInfo_.expiry);

        /* Burn discount pass */
        DiscountPassToken(yieldPassInfo_.discountPass).burn(tokenId);

        /* Emit Redeemed */
        emit Redeemed(msg.sender, yieldPass, yieldPassInfo_.token, yieldPassInfo_.discountPass, tokenId, teardownData);

        return teardownData;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function withdraw(
        address yieldPass,
        uint256 tokenId,
        bytes calldata harvestData,
        bytes calldata teardownData
    ) external nonReentrant {
        /* Harvest yield */
        _harvest(yieldPass, harvestData);

        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Validate block timestamp > expiry */
        if (block.timestamp <= yieldPassInfo_.expiry) revert InvalidWindow();

        /* Validate caller burned token */
        if (yieldPassState.tokenIdRedemptions[tokenId] != msg.sender) revert InvalidWithdrawal();

        /* Delete redemption */
        delete yieldPassState.tokenIdRedemptions[tokenId];

        /* Call yield adapter teardown hook */
        _yieldPassStates[yieldPass].yieldAdapter.teardown(tokenId, msg.sender, teardownData);

        /* Validate caller owns token ID */
        if (IERC721(yieldPassInfo_.token).ownerOf(tokenId) != msg.sender) revert InvalidWithdrawal();

        /* Emit Withdrawn */
        emit Withdrawn(msg.sender, yieldPass, yieldPassInfo_.token, yieldPassInfo_.discountPass, tokenId);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPass
     */
    function deployYieldPass(
        address token,
        uint64 startTime,
        uint64 expiry,
        bool isTransferable,
        address adapter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address, address) {
        /* Validate expiry */
        if (expiry == 0 || startTime >= expiry) revert InvalidExpiry();

        /* Validate adapter is valid */
        if (adapter == address(0)) revert InvalidAdapter();

        /* Compute deployment hash based on token, and expiry */
        bytes32 deploymentHash = _getDeploymentHash(token, expiry);

        /* Compute yield pass token creation bytecode */
        bytes memory yieldPassBytecode =
            abi.encodePacked(type(YieldPassToken).creationCode, _getCtorParam(true, token, expiry, false));

        /* Compute expected yield pass token address */
        address yieldPass = Create2.computeAddress(deploymentHash, keccak256(yieldPassBytecode));

        /* Validate deployment does not exist */
        if (_yieldPassInfos[yieldPass].expiry != 0) revert AlreadyDeployed();

        /* Create yield pass token */
        Create2.deploy(0, deploymentHash, yieldPassBytecode);

        /* Create discount pass */
        address discountPass = Create2.deploy(
            0,
            deploymentHash,
            abi.encodePacked(type(DiscountPassToken).creationCode, _getCtorParam(false, token, expiry, isTransferable))
        );

        /* Store yield pass info */
        _yieldPassInfos[yieldPass] = YieldPassInfo({
            startTime: startTime,
            expiry: expiry,
            token: token,
            yieldPass: yieldPass,
            discountPass: discountPass
        });

        /* Add yield pass to array */
        _yieldPasses.push(yieldPass);

        /* Set yield adapter */
        _yieldPassStates[yieldPass].yieldAdapter = IYieldAdapter(adapter);

        /* Emit YieldPassDeployed */
        emit YieldPassDeployed(token, expiry, yieldPass, discountPass, adapter);

        return (yieldPass, discountPass);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function setYieldAdapter(address yieldPass, address adapter) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Update adapter */
        _yieldPassStates[yieldPass].yieldAdapter = IYieldAdapter(adapter);

        emit AdapterUpdated(yieldPass, adapter);
    }

    function setTransferable(address yieldPass, bool isTransferable) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Update transferability */
        DiscountPassToken(yieldPassInfo_.discountPass).setTransferable(isTransferable);
    }
}
