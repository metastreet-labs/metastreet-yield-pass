// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IYieldPass} from "./interfaces/IYieldPass.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {YieldPassToken} from "./YieldPassToken.sol";
import {NodePassToken} from "./NodePassToken.sol";

/**
 * @title Yield Pass
 * @author MetaStreet Foundation
 */
contract YieldPass is IYieldPass, ReentrancyGuard, AccessControl, Multicall, ERC721Holder, EIP712 {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.1";

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
     * @param redemptions Map of redemption hash to withdraw account
     */
    struct YieldPassState {
        YieldClaimState claimState;
        mapping(bytes32 => address) redemptions;
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

        /* Compute yield pass token amount based on node count and yield pass's time to expiry */
        return (1 ether * (yieldPassInfo_.expiryTime - block.timestamp) * count)
            / (yieldPassInfo_.expiryTime - yieldPassInfo_.startTime);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper to get deployment hash
     * @param nodeToken Node token
     * @param expiryTime Expiry timestamp
     * @return Deployment hash
     */
    function _getDeploymentHash(address nodeToken, uint256 expiryTime) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(nodeToken, expiryTime));
    }

    /**
     * @notice Helper to get yield pass token constructor parameters
     * @param nodeToken Node token
     * @param expiryTime Expiry timestamp
     * @return Encoded constructor parameters
     */
    function _getYieldPassCtorParams(address nodeToken, uint256 expiryTime) internal view returns (bytes memory) {
        /* Construct yield pass name and symbol */
        string memory tokenName = string.concat(
            IERC721Metadata(nodeToken).name(), " (Yield Pass - Expiry: ", Strings.toString(expiryTime), ")"
        );
        string memory tokenSymbol =
            string.concat(IERC721Metadata(nodeToken).symbol(), "-YP-", Strings.toString(expiryTime));

        return abi.encode(tokenName, tokenSymbol);
    }

    /**
     * @notice Helper to get node pass token constructor parameters
     * @param nodeToken Node token
     * @param expiryTime Expiry timestamp
     * @param yieldPass Yield pass token
     * @return Encoded constructor parameters
     */
    function _getNodePassCtorParams(
        address nodeToken,
        uint256 expiryTime,
        address yieldPass
    ) internal view returns (bytes memory) {
        /* Construct node pass name and symbol */
        string memory tokenName = string.concat(
            IERC721Metadata(nodeToken).name(), " (Node Pass - Expiry: ", Strings.toString(expiryTime), ")"
        );
        string memory tokenSymbol =
            string.concat(IERC721Metadata(nodeToken).symbol(), "-NP-", Strings.toString(expiryTime));

        return abi.encode(tokenName, tokenSymbol, yieldPass);
    }

    /**
     * @notice Validate transfer signature of node owner
     * @param account Account owning nodes
     * @param proxyAccount Proxy account
     * @param deadline Deadline
     * @param nodeTokenIds Node token IDs
     * @param signature Transfer signature
     */
    function _validateTransferSignature(
        address account,
        address proxyAccount,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata signature
    ) internal view {
        /* Encode token IDs */
        bytes memory encodedTokenIds;
        for (uint256 i; i < nodeTokenIds.length; i++) {
            encodedTokenIds = bytes.concat(encodedTokenIds, abi.encode(nodeTokenIds[i]));
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
     * @notice Mint helper
     */
    function _mint(
        address yieldPass,
        address account,
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) internal returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate mint window is open */
        if (block.timestamp < yieldPassInfo_.startTime || block.timestamp >= yieldPassInfo_.expiryTime) {
            revert InvalidWindow();
        }

        /* Validate deadline */
        if (deadline < block.timestamp) revert InvalidDeadline();

        /* Verify transfer signature if caller is proxy account */
        if (account != msg.sender) {
            _validateTransferSignature(account, msg.sender, deadline, nodeTokenIds, transferSignature);
        }

        /* Quote mint amount */
        uint256 yieldPassAmount = quoteMint(yieldPass, nodeTokenIds.length);

        /* Update claim state shares */
        _yieldPassStates[yieldPass].claimState.shares += yieldPassAmount;

        /* Call yield adapter setup hook */
        address[] memory operators = IYieldAdapter(yieldPassInfo_.yieldAdapter).setup(account, nodeTokenIds, setupData);

        /* Mint yield pass token */
        YieldPassToken(yieldPass).mint(yieldPassRecipient, yieldPassAmount);

        /* Mint node pass tokens */
        NodePassToken(yieldPassInfo_.nodePass).mint(nodePassRecipient, nodeTokenIds);

        /* Emit Minted */
        emit Minted(
            yieldPass,
            yieldPassInfo_.nodePass,
            account,
            yieldPassRecipient,
            yieldPassAmount,
            nodePassRecipient,
            yieldPassInfo_.nodeToken,
            nodeTokenIds,
            operators
        );

        return yieldPassAmount;
    }

    /**
     * @inheritdoc IYieldPass
     */
    function mint(
        address yieldPass,
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData
    ) external nonReentrant returns (uint256) {
        return _mint(
            yieldPass,
            msg.sender,
            yieldPassRecipient,
            nodePassRecipient,
            deadline,
            nodeTokenIds,
            setupData,
            msg.data[0:0]
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function mint(
        address yieldPass,
        address account,
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) external nonReentrant returns (uint256) {
        return _mint(
            yieldPass,
            account,
            yieldPassRecipient,
            nodePassRecipient,
            deadline,
            nodeTokenIds,
            setupData,
            transferSignature
        );
    }

    /**
     * @inheritdoc IYieldPass
     */
    function harvest(address yieldPass, bytes calldata harvestData) external nonReentrant returns (uint256) {
        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Harvest yield */
        uint256 yieldAmount = IYieldAdapter(yieldPassInfo_.yieldAdapter).harvest(harvestData);

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
    function redeem(address yieldPass, address recipient, uint256[] calldata nodeTokenIds) external nonReentrant {
        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Validate token IDs length */
        if (nodeTokenIds.length == 0) revert InvalidTokenIds();

        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Validate yield pass is expired */
        if (block.timestamp <= yieldPassInfo_.expiryTime) revert InvalidWindow();

        /* Create encoded token IDs */
        bytes memory encodedTokenIds;
        for (uint256 i; i < nodeTokenIds.length; i++) {
            /* Validate caller owns node pass */
            if (NodePassToken(yieldPassInfo_.nodePass).ownerOf(nodeTokenIds[i]) != msg.sender) {
                revert InvalidRedemption();
            }

            /* Validate token ID is unique and sorted in ascending order */
            if (i != nodeTokenIds.length - 1 && nodeTokenIds[i] >= nodeTokenIds[i + 1]) revert InvalidTokenIds();

            /* Encode token IDs */
            encodedTokenIds = abi.encodePacked(encodedTokenIds, nodeTokenIds[i]);

            /* Burn node pass token */
            NodePassToken(yieldPassInfo_.nodePass).burn(nodeTokenIds[i]);
        }

        /* Compute redemption hash */
        bytes32 redemptionHash = keccak256(encodedTokenIds);

        /* Store redemption address */
        _yieldPassStates[yieldPass].redemptions[redemptionHash] = msg.sender;

        /* Call yield adapter redeem hook */
        IYieldAdapter(yieldPassInfo_.yieldAdapter).redeem(recipient, nodeTokenIds, redemptionHash);

        /* Emit Redeemed */
        emit Redeemed(yieldPass, yieldPassInfo_.nodePass, msg.sender, recipient, yieldPassInfo_.nodeToken, nodeTokenIds);
    }

    /**
     * @inheritdoc IYieldPass
     */
    function withdraw(address yieldPass, uint256[] calldata nodeTokenIds) external nonReentrant {
        /* Validate token IDs length */
        if (nodeTokenIds.length == 0) revert InvalidTokenIds();

        /* Get yield pass info */
        YieldPassInfo memory yieldPassInfo_ = yieldPassInfo(yieldPass);

        /* Create encoded token IDs */
        bytes memory encodedTokenIds;
        for (uint256 i; i < nodeTokenIds.length; i++) {
            /* Validate token ID is unique and sorted in ascending order */
            if (i != nodeTokenIds.length - 1 && nodeTokenIds[i] >= nodeTokenIds[i + 1]) revert InvalidTokenIds();

            /* Encode token ID */
            encodedTokenIds = abi.encodePacked(encodedTokenIds, nodeTokenIds[i]);
        }

        /* Compute redemption hash */
        bytes32 redemptionHash = keccak256(encodedTokenIds);

        /* Validate caller is redemption address */
        if (_yieldPassStates[yieldPass].redemptions[redemptionHash] != msg.sender) revert InvalidWithdrawal();

        /* Delete redemption */
        delete _yieldPassStates[yieldPass].redemptions[redemptionHash];

        /* Call yield adapter withdraw hook */
        address recipient = IYieldAdapter(yieldPassInfo_.yieldAdapter).withdraw(nodeTokenIds, redemptionHash);

        /* Emit Withdrawn */
        emit Withdrawn(
            yieldPass, yieldPassInfo_.nodePass, msg.sender, recipient, yieldPassInfo_.nodeToken, nodeTokenIds
        );
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldPass
     */
    function deployYieldPass(
        address nodeToken,
        uint64 startTime,
        uint64 expiryTime,
        address adapter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address, address) {
        /* Validate expiry */
        if (expiryTime == 0 || startTime >= expiryTime) revert InvalidExpiry();

        /* Validate adapter */
        if (adapter == address(0)) revert InvalidAdapter();

        /* Compute deployment hash based on node token and expiry */
        bytes32 deploymentHash = _getDeploymentHash(nodeToken, expiryTime);

        /* Create yield pass token */
        address yieldPass = Create2.deploy(
            0,
            deploymentHash,
            abi.encodePacked(type(YieldPassToken).creationCode, _getYieldPassCtorParams(nodeToken, expiryTime))
        );

        /* Create node pass token */
        address nodePass = Create2.deploy(
            0,
            deploymentHash,
            abi.encodePacked(type(NodePassToken).creationCode, _getNodePassCtorParams(nodeToken, expiryTime, yieldPass))
        );

        /* Store yield pass info */
        _yieldPassInfos[yieldPass] = YieldPassInfo({
            startTime: startTime,
            expiryTime: expiryTime,
            nodeToken: nodeToken,
            yieldPass: yieldPass,
            nodePass: nodePass,
            yieldAdapter: adapter
        });

        /* Add yield pass to array */
        _yieldPasses.push(yieldPass);

        /* Emit YieldPassDeployed */
        emit YieldPassDeployed(yieldPass, nodePass, nodeToken, startTime, expiryTime, adapter);

        return (yieldPass, nodePass);
    }
}
