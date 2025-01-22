// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
import {NodePassToken} from "./NodePassToken.sol";

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
        keccak256("TransferApproval(address proxyAccount,uint256 deadline,uint256[] tokenIds)");

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass state
     * @param claimState Yield claim state
     * @param tokenIdRedemptions Map of token ID to redemption address
     */
    struct YieldPassState {
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
     * @notice Array of deployed yield pass tokens
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
        if (_yieldPassInfos[yieldPass].expiryTime == 0) revert InvalidYieldPass();
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
            yieldPassInfos_[i - offset] = _yieldPassInfos[_yieldPasses[i]];
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
    function cumulativeYield(
        address yieldPass
    ) public view returns (uint256) {
        return IYieldAdapter(yieldPassInfo(yieldPass).yieldAdapter).cumulativeYield();
    }

    /**
     * @inheritdoc IYieldPass
     */
    function cumulativeYield(address yieldPass, uint256 yieldPassAmount) public view returns (uint256) {
        return Math.mulDiv(
            IYieldAdapter(yieldPassInfo(yieldPass).yieldAdapter).cumulativeYield(),
            yieldPassAmount,
            _yieldPassStates[yieldPass].claimState.shares
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claimableYield(
        address yieldPass
    ) public view returns (uint256) {
        return _yieldPassStates[yieldPass].claimState.total;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claimableYield(address yieldPass, uint256 yieldPassAmount) public view returns (uint256) {
        return Math.mulDiv(
            _yieldPassStates[yieldPass].claimState.total, yieldPassAmount, _yieldPassStates[yieldPass].claimState.shares
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function quoteMint(address yieldPass, uint256 count) public view returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate mint window is open */
        if (block.timestamp < yieldPassInfo_.startTime || block.timestamp >= yieldPassInfo_.expiryTime) {
            revert InvalidWindow();
        }

        /* Compute yield pass token amount based on NFT count and yield pass's time to expiry */
        return (1 ether * (yieldPassInfo_.expiryTime - block.timestamp) * count)
            / (yieldPassInfo_.expiryTime - yieldPassInfo_.startTime);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper to get deployment hash
     * @param token Token address
     * @param expiryTime Expiry timestamp
     * @return Deployment hash
     */
    function _getDeploymentHash(address token, uint256 expiryTime) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, expiryTime));
    }

    /**
     * @notice Helper to get yield pass token constructor parameters
     * @param token NFT token
     * @param expiryTime Expiry timestamp
     * @return Encoded constructor parameters
     */
    function _getYieldPassCtorParams(address token, uint256 expiryTime) internal view returns (bytes memory) {
        /* Construct yield pass name and symbol */
        string memory tokenName =
            string.concat(IERC721Metadata(token).name(), " (Yield Pass - Expiry: ", Strings.toString(expiryTime), ")");
        string memory tokenSymbol = string.concat(IERC721Metadata(token).symbol(), "-YP-", Strings.toString(expiryTime));

        return abi.encode(tokenName, tokenSymbol);
    }

    /**
     * @notice Helper to get node pass token constructor parameters
     * @param token NFT token
     * @param expiryTime Expiry timestamp
     * @param isUserLocked True if token is user locked, otherwise false
     * @return Encoded constructor parameters
     */
    function _getNodePassCtorParams(
        address token,
        uint256 expiryTime,
        bool isUserLocked
    ) internal view returns (bytes memory) {
        /* Construct node pass name and symbol */
        string memory tokenName =
            string.concat(IERC721Metadata(token).name(), " (Node Pass - Expiry: ", Strings.toString(expiryTime), ")");
        string memory tokenSymbol = string.concat(IERC721Metadata(token).symbol(), "-DP-", Strings.toString(expiryTime));

        return abi.encode(tokenName, tokenSymbol, isUserLocked);
    }

    /**
     * @notice Validate transfer signature of NFT owner
     * @param account Account owning NFTs
     * @param proxyAccount Proxy account
     * @param deadline Deadline
     * @param tokenIds NFT token IDs
     * @param signature Transfer signature
     */
    function _validateTransferSignature(
        address account,
        address proxyAccount,
        uint256 deadline,
        uint256[] calldata tokenIds,
        bytes calldata signature
    ) internal view {
        /* Encode token IDs */
        bytes memory encodedTokenIds;
        for (uint256 i; i < tokenIds.length; i++) {
            encodedTokenIds = bytes.concat(encodedTokenIds, abi.encode(tokenIds[i]));
        }

        /* Recover transfer approval signer */
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(abi.encode(TRANSFER_APPROVAL_TYPEHASH, proxyAccount, deadline, keccak256(encodedTokenIds)))
            ),
            signature
        );

        /* Validate signer */
        if (signer != account) revert InvalidSignature();
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
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata tokenIds,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) external nonReentrant returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate deadline */
        if (deadline < block.timestamp) revert InvalidDeadline();

        /* Verify transfer signature if caller is proxy account */
        if (account != msg.sender) {
            _validateTransferSignature(account, msg.sender, deadline, tokenIds, transferSignature);
        }

        /* Quote mint amount */
        uint256 yieldPassAmount = quoteMint(yieldPass, tokenIds.length);

        /* Update claim state shares */
        _yieldPassStates[yieldPass].claimState.shares += yieldPassAmount;

        /* Call yield adapter setup hook */
        address[] memory operators =
            IYieldAdapter(yieldPassInfo_.yieldAdapter).setup(yieldPassInfo_.expiryTime, account, tokenIds, setupData);

        /* Mint yield pass token */
        YieldPassToken(yieldPass).mint(yieldPassRecipient, yieldPassAmount);

        /* Mint node pass tokens */
        NodePassToken(yieldPassInfo_.nodePass).mint(nodePassRecipient, tokenIds);

        /* Emit Minted */
        emit Minted(
            yieldPass,
            yieldPassInfo_.nodePass,
            yieldPassRecipient,
            yieldPassAmount,
            nodePassRecipient,
            yieldPassInfo_.token,
            tokenIds,
            operators
        );

        return yieldPassAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function harvest(address yieldPass, bytes calldata harvestData) external nonReentrant returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Harvest yield */
        uint256 yieldAmount = IYieldAdapter(yieldPassInfo_.yieldAdapter).harvest(yieldPassInfo_.expiryTime, harvestData);

        /* Update yield claim state */
        _yieldPassStates[yieldPass].claimState.balance += yieldAmount;
        _yieldPassStates[yieldPass].claimState.total += yieldAmount;

        /* Emit Harvested */
        emit Harvested(yieldPass, yieldAmount);

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function claim(
        address yieldPass,
        address recipient,
        uint256 yieldPassAmount
    ) external nonReentrant returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate yield pass is expired */
        if (block.timestamp <= yieldPassInfo_.expiryTime) revert InvalidWindow();

        /* Validate yield pass amount */
        if (yieldPassAmount == 0 || YieldPassToken(yieldPass).balanceOf(msg.sender) < yieldPassAmount) {
            revert InvalidAmount();
        }

        /* Compute yield amount */
        uint256 yieldAmount = claimableYield(yieldPass, yieldPassAmount);

        /* Update yield claim state */
        _yieldPassStates[yieldPass].claimState.balance -= yieldAmount;

        /* Burn yield pass amount */
        YieldPassToken(yieldPass).burn(msg.sender, yieldPassAmount);

        /* Call yield adapter claim hook to transfer yield amount to recipient */
        IYieldAdapter(yieldPassInfo_.yieldAdapter).claim(recipient, yieldAmount);

        /* Emit Claimed */
        emit Claimed(
            yieldPass,
            msg.sender,
            yieldPassAmount,
            recipient,
            IYieldAdapter(yieldPassInfo_.yieldAdapter).token(),
            yieldAmount
        );

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function redeem(address yieldPass, uint256[] calldata tokenIds) external nonReentrant {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate caller owns node pass */
            if (NodePassToken(yieldPassInfo_.nodePass).ownerOf(tokenIds[i]) != msg.sender) {
                revert InvalidRedemption();
            }

            /* Store redemption address */
            _yieldPassStates[yieldPass].tokenIdRedemptions[tokenIds[i]] = msg.sender;

            /* Burn node pass */
            NodePassToken(yieldPassInfo_.nodePass).burn(msg.sender, tokenIds[i]);
        }

        /* Call yield adapter initiate withdraw hook */
        IYieldAdapter(yieldPassInfo_.yieldAdapter).initiateWithdraw(yieldPassInfo_.expiryTime, tokenIds);

        /* Emit Redeemed */
        emit Redeemed(yieldPass, yieldPassInfo_.nodePass, msg.sender, yieldPassInfo_.token, tokenIds);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function withdraw(address yieldPass, address recipient, uint256[] calldata tokenIds) external nonReentrant {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate yield pass is expired */
        if (block.timestamp <= yieldPassInfo_.expiryTime) revert InvalidWindow();

        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate caller burned token */
            if (_yieldPassStates[yieldPass].tokenIdRedemptions[tokenIds[i]] != msg.sender) revert InvalidWithdrawal();

            /* Delete redemption */
            delete _yieldPassStates[yieldPass].tokenIdRedemptions[tokenIds[i]];
        }

        /* Call yield adapter withdraw hook */
        IYieldAdapter(yieldPassInfo_.yieldAdapter).withdraw(recipient, tokenIds);

        /* Emit Withdrawn */
        emit Withdrawn(yieldPass, yieldPassInfo_.nodePass, msg.sender, recipient, yieldPassInfo_.token, tokenIds);
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
        uint64 expiryTime,
        bool isUserLocked,
        address adapter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address, address) {
        /* Validate expiry */
        if (expiryTime == 0 || startTime >= expiryTime) revert InvalidExpiry();

        /* Validate adapter */
        if (adapter == address(0)) revert InvalidAdapter();

        /* Compute deployment hash based on token and expiry */
        bytes32 deploymentHash = _getDeploymentHash(token, expiryTime);

        /* Create yield pass token */
        address yieldPass = Create2.deploy(
            0,
            deploymentHash,
            abi.encodePacked(type(YieldPassToken).creationCode, _getYieldPassCtorParams(token, expiryTime))
        );

        /* Create node pass token */
        address nodePass = Create2.deploy(
            0,
            deploymentHash,
            abi.encodePacked(type(NodePassToken).creationCode, _getNodePassCtorParams(token, expiryTime, isUserLocked))
        );

        /* Store yield pass info */
        _yieldPassInfos[yieldPass] = YieldPassInfo({
            startTime: startTime,
            expiryTime: expiryTime,
            token: token,
            yieldPass: yieldPass,
            nodePass: nodePass,
            yieldAdapter: adapter
        });

        /* Add yield pass to array */
        _yieldPasses.push(yieldPass);

        /* Emit YieldPassDeployed */
        emit YieldPassDeployed(yieldPass, nodePass, token, startTime, expiryTime, adapter);

        return (yieldPass, nodePass);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function setUserLocked(address yieldPass, bool isUserLocked) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Update user locked */
        NodePassToken(yieldPassInfo_.nodePass).setUserLocked(isUserLocked);
    }
}
