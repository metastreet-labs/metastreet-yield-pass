// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IYieldPass} from "./interfaces/IYieldPass.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {YieldPassToken} from "./YieldPassToken.sol";
import {DiscountPassToken} from "./DiscountPassToken.sol";

/**
 * @title Yield Pass
 * @author MetaStreet Foundation
 */
contract YieldPass is IYieldPass, ReentrancyGuard, AccessControl, Multicall, ERC721Holder, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Signing domain version
     */
    string public constant DOMAIN_VERSION = "1.0";

    /**
     * @notice Transfer approval EIP-712 typehash
     */
    bytes32 public constant TRANSFER_APPROVAL_TYPEHASH =
        keccak256("TransferApproval(address proxyAccount,uint256 nonce,uint256[] tokenIds)");

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass state
     * @param yieldAdapter Yield adapter
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
     * @notice Map of yield pass token to yield pass info
     */
    mapping(address => YieldPassInfo) internal _yieldPassInfos;

    /**
     * @notice Map of yield pass token to yield pass state
     */
    mapping(address => YieldPassState) internal _yieldPassStates;

    /**
     * @notice Map of account to nonce
     */
    mapping(address => uint256) internal _nonces;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldPass constructor
     */
    constructor() EIP712(name(), DOMAIN_VERSION) {
        /* Disable initialization of implementation contract */
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
    function name() public pure returns (string memory) {
        return "MetaStreet Yield Pass";
    }

    /**
     * @inheritdoc IYieldPass
     */
    function yieldPassInfo(
        address yieldPass
    ) public view returns (YieldPassInfo memory) {
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
    function claimState(
        address yieldPass
    ) public view returns (YieldClaimState memory) {
        return _yieldPassStates[yieldPass].claimState;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function yieldAdapter(
        address yieldPass
    ) public view returns (address) {
        return address(_yieldPassStates[yieldPass].yieldAdapter);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function nonce(
        address account
    ) public view returns (uint256) {
        return _nonces[account];
    }

    /**
     * @inheritdoc IYieldPass
     */
    function cumulativeYield(
        address yieldPass
    ) public view returns (uint256) {
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
    function quoteMint(address yieldPass, uint256 count) public view returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Validate yield pass is deployed */
        if (yieldPassInfo_.expiry == 0) revert InvalidYieldPass();

        /* Validate mint window is open */
        if (block.timestamp < yieldPassInfo_.startTime || block.timestamp >= yieldPassInfo_.expiry) {
            revert InvalidWindow();
        }

        /* Compute yield pass token amount based on this yield pass's time to expiry */
        return (1 ether * (yieldPassInfo_.expiry - block.timestamp) * count)
            / (yieldPassInfo_.expiry - yieldPassInfo_.startTime);
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
     * @notice Helper to get yield pass token constructor parameters
     * @param token NFT token
     * @param expiry Expiry
     * @return Encoded constructor parameters
     */
    function _getYieldPassCtorParams(address token, uint256 expiry) internal view returns (bytes memory) {
        /* Construct yield pass name and symbol */
        string memory tokenName =
            string.concat(IERC721Metadata(token).name(), " (Yield Pass - Expiry: ", Strings.toString(expiry), ")");
        string memory tokenSymbol = string.concat(IERC721Metadata(token).symbol(), "-YP-", Strings.toString(expiry));

        return abi.encode(tokenName, tokenSymbol);
    }

    /**
     * @notice Helper to get discount pass token constructor parameters
     * @param token NFT token
     * @param expiry Expiry
     * @param isUserLocked True if token is user locked
     * @return Encoded constructor parameters
     */
    function _getDiscountPassCtorParams(
        address token,
        uint256 expiry,
        bool isUserLocked
    ) internal view returns (bytes memory) {
        /* Construct discount pass name and symbol */
        string memory tokenName =
            string.concat(IERC721Metadata(token).name(), " (Discount Pass - Expiry: ", Strings.toString(expiry), ")");
        string memory tokenSymbol = string.concat(IERC721Metadata(token).symbol(), "-DP-", Strings.toString(expiry));

        return abi.encode(tokenName, tokenSymbol, isUserLocked);
    }

    /**
     * @notice Validate transfer signature of NFT owner and increase nonce
     * @param account Account holding NFTs
     * @param proxyAccount Proxy account
     * @param tokenIds NFT token IDs
     * @param signature Transfer signature
     */
    function _validateTransferSignature(
        address account,
        address proxyAccount,
        uint256[] calldata tokenIds,
        bytes calldata signature
    ) internal {
        /* Recover account address */
        address accountAddress = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(abi.encode(TRANSFER_APPROVAL_TYPEHASH, proxyAccount, _nonces[account], tokenIds))
            ),
            signature
        );

        /* Validate account */
        if (accountAddress != account) revert InvalidSignature();

        /* Increment nonce */
        _nonces[account]++;
    }

    /*------------------------------------------------------------------------*/
    /* User API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPass
     */
    function mint(
        address yieldPass,
        address account,
        uint256[] calldata tokenIds,
        address yieldPassRecipient,
        address discountPassRecipient,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) external nonReentrant returns (uint256) {
        /* Verify transfer signature if caller is proxy account */
        if (account != msg.sender) {
            _validateTransferSignature(account, msg.sender, tokenIds, transferSignature);
        }

        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Quote mint amount */
        uint256 yieldPassAmount = quoteMint(yieldPass, tokenIds.length);

        /* Update claim state shares */
        _yieldPassStates[yieldPass].claimState.shares += yieldPassAmount;

        /* Call yield adapter setup hook */
        address[] memory operators =
            _yieldPassStates[yieldPass].yieldAdapter.setup(tokenIds, yieldPassInfo_.expiry, account, setupData);

        /* Mint yield pass token */
        YieldPassToken(yieldPass).mint(yieldPassRecipient, yieldPassAmount);

        /* Mint discount pass tokens */
        DiscountPassToken(yieldPassInfo_.discountPass).mint(discountPassRecipient, tokenIds);

        /* Emit Minted */
        emit Minted(
            msg.sender,
            yieldPass,
            yieldPassInfo_.token,
            yieldPassAmount,
            yieldPassInfo_.discountPass,
            tokenIds,
            operators
        );

        return yieldPassAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function harvest(address yieldPass, bytes calldata harvestData) external nonReentrant returns (uint256) {
        /* Validate yield pass is deployed */
        if (_yieldPassInfos[yieldPass].expiry == 0) revert InvalidYieldPass();

        IYieldAdapter yieldAdapter_ = _yieldPassStates[yieldPass].yieldAdapter;

        /* Harvest yield */
        uint256 amount = yieldAdapter_.harvest(_yieldPassInfos[yieldPass].expiry, harvestData);

        _yieldPassStates[yieldPass].claimState.balance += amount;
        _yieldPassStates[yieldPass].claimState.total += amount;

        /* Emit Harvested */
        emit Harvested(yieldPass, amount);

        return amount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claim(
        address yieldPass,
        address recipient,
        uint256 yieldPassAmount
    ) external nonReentrant returns (uint256) {
        /* Validate yield pass amount */
        if (yieldPassAmount == 0 || YieldPassToken(yieldPass).balanceOf(msg.sender) < yieldPassAmount) {
            revert InvalidAmount();
        }

        /* Validate expiry is in the past */
        if (block.timestamp <= _yieldPassInfos[yieldPass].expiry) revert InvalidWindow();

        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        /* Compute yield amount */
        uint256 yieldAmount = claimable(yieldPass, yieldPassAmount);

        /* Update yield claim state */
        yieldPassState.claimState.balance -= yieldAmount;

        /* Burn yield pass amount */
        YieldPassToken(yieldPass).burn(msg.sender, yieldPassAmount);

        /* Call yield adapter claim hook to transfer yield amount to caller */
        address yieldToken = yieldPassState.yieldAdapter.claim(msg.sender, yieldAmount);

        /* Emit Claimed */
        emit Claimed(msg.sender, yieldPass, recipient, yieldPassAmount, yieldToken, yieldAmount);

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function redeem(address yieldPass, uint256[] calldata tokenIds) external nonReentrant returns (bytes memory) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate caller owns discount pass */
            if (DiscountPassToken(yieldPassInfo_.discountPass).ownerOf(tokenIds[i]) != msg.sender) {
                revert InvalidRedemption();
            }

            /* Store redemption address */
            yieldPassState.tokenIdRedemptions[tokenIds[i]] = msg.sender;

            /* Burn discount pass */
            DiscountPassToken(yieldPassInfo_.discountPass).burn(msg.sender, tokenIds[i]);
        }

        /* Call yield adapter initiate teardown hook */
        bytes memory teardownData = yieldPassState.yieldAdapter.initiateTeardown(tokenIds, yieldPassInfo_.expiry);

        /* Emit Redeemed */
        emit Redeemed(msg.sender, yieldPass, yieldPassInfo_.token, yieldPassInfo_.discountPass, tokenIds, teardownData);

        return teardownData;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function withdraw(address yieldPass, address recipient, uint256[] calldata tokenIds) external nonReentrant {
        /* Get yield pass state */
        YieldPassState storage yieldPassState = _yieldPassStates[yieldPass];

        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Validate block timestamp > expiry */
        if (block.timestamp <= yieldPassInfo_.expiry) revert InvalidWindow();

        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate caller burned token */
            if (yieldPassState.tokenIdRedemptions[tokenIds[i]] != msg.sender) revert InvalidWithdrawal();

            /* Delete redemption */
            delete yieldPassState.tokenIdRedemptions[tokenIds[i]];
        }

        /* Call yield adapter teardown hook */
        _yieldPassStates[yieldPass].yieldAdapter.teardown(tokenIds, recipient);

        /* Validate caller owns token IDs */
        for (uint256 i; i < tokenIds.length; i++) {
            if (IERC721(yieldPassInfo_.token).ownerOf(tokenIds[i]) != recipient) revert InvalidWithdrawal();
        }

        /* Emit Withdrawn */
        emit Withdrawn(msg.sender, yieldPass, yieldPassInfo_.token, recipient, yieldPassInfo_.discountPass, tokenIds);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function increaseNonce() external nonReentrant {
        _nonces[msg.sender]++;

        emit NonceIncreased(msg.sender, _nonces[msg.sender]);
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
        bool isUserLocked,
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
            abi.encodePacked(type(YieldPassToken).creationCode, _getYieldPassCtorParams(token, expiry));

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
            abi.encodePacked(
                type(DiscountPassToken).creationCode, _getDiscountPassCtorParams(token, expiry, isUserLocked)
            )
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
        emit YieldPassDeployed(token, expiry, yieldPass, startTime, discountPass, adapter);

        return (yieldPass, discountPass);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function setUserLocked(address yieldPass, bool isUserLocked) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = _yieldPassInfos[yieldPass];

        /* Update user locked */
        DiscountPassToken(yieldPassInfo_.discountPass).setUserLocked(isUserLocked);
    }
}
