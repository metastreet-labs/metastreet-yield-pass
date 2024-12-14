// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

/**
 * @title IERC4907 Interface
 */
interface IERC4907 {
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    function setUser(uint256 tokenId, address user, uint64 expires) external;
    function userOf(
        uint256 tokenId
    ) external view returns (address);
    function userExpires(
        uint256 tokenId
    ) external view returns (uint256);
}

/**
 * @title Aethir Checker Claim And Withdraw Interface
 */
interface ICheckerClaimAndWithdraw {
    function aethirTokenAdress() external view returns (address);
    function withdraw(uint256[] memory orderIds, uint48 expiryTimestamp, bytes[] memory signatures) external;
    function claim(
        uint256 orderId,
        uint48 cliffSeconds,
        uint48 expiryTimestamp,
        uint256 amount,
        bytes[] memory signatures
    ) external;
}

/**
 * @title Aethir Yield Adapter
 * @author MetaStreet Foundation
 */
contract AethirYieldAdapter is IYieldAdapter, ERC721Holder, AccessControl, EIP712, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

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
     * @notice Validated Nodes EIP-712 typehash
     */
    bytes32 public constant VALIDATED_NODES_TYPEHASH = keccak256(
        "ValidatedNodes(uint256[] tokenIds,address[] burnerWallets,uint64[] subscriptionExpiries,uint64 timestamp,uint64 duration)"
    );

    /*------------------------------------------------------------------------*/
    /* Access Control Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass role
     */
    bytes32 public constant YIELD_PASS_ROLE = keccak256("YIELD_PASS_ROLE");

    /**
     * @notice Pause admin role
     */
    bytes32 public constant PAUSE_ADMIN_ROLE = keccak256("PAUSE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid length
     */
    error InvalidLength();

    /**
     * @notice Invalid token ID
     */
    error InvalidTokenId();

    /**
     * @notice Invalid timestamp
     */
    error InvalidTimestamp();

    /**
     * @notice Invalid expiry
     */
    error InvalidExpiry();

    /**
     * @notice Invalid signature
     */
    error InvalidSignature();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Invalid cliff seconds
     */
    error InvalidCliff();

    /**
     * @notice Invalid claim
     */
    error InvalidClaim();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Cliff seconds updated
     * @param cliffSeconds New cliff seconds
     */
    event CliffSecondsUpdated(uint48 cliffSeconds);

    /**
     * @notice Signer updated
     * @param signer New signer address
     */
    event SignerUpdated(address signer);

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Aethir Claim data
     * @param orderId Order ID
     * @param cliffSeconds Cliff period in seconds
     * @param expiryTimestamp Expiry timestamp
     * @param amount Amount to claim
     * @param signatureArray Signatures
     */
    struct AethirClaimData {
        uint256 orderId;
        uint48 cliffSeconds;
        uint48 expiryTimestamp;
        uint256 amount;
        bytes[] signatureArray;
    }

    /**
     * @notice Aethir Withdraw data
     * @param orderIdArray Order IDs
     * @param expiryTimestamp Expiry timestamp
     * @param signatureArray Signatures
     */
    struct AethirWithdrawData {
        uint256[] orderIdArray;
        uint48 expiryTimestamp;
        bytes[] signatureArray;
    }

    /**
     * @notice Validated nodes
     * @param tokenIds Token IDs
     * @param burnerWallets Burner wallet addresses
     * @param subscriptionExpiries Subscription expiry timestamps
     * @param timestamp Timestamp
     * @param duration Validity duration
     */
    struct ValidatedNodes {
        uint256[] tokenIds;
        address[] burnerWallets;
        uint64[] subscriptionExpiries;
        uint64 timestamp;
        uint64 duration;
    }

    /**
     * @notice Validated nodes with signature
     * @param nodes Validated nodes
     * @param signature Signature
     */
    struct SignedValidatedNodes {
        ValidatedNodes nodes;
        bytes signature;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass
     */
    address internal immutable _yieldPass;

    /**
     * @notice Aethir Checker node license
     */
    address internal immutable _aethirCheckerNodeLicense;

    /**
     * @notice Aethir Checker claim and withdraw
     */
    ICheckerClaimAndWithdraw internal immutable _aethirCheckerClaimAndWithdraw;

    /**
     * @notice ATH token
     */
    IERC20 internal immutable _athToken;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Cliff seconds
     */
    uint48 internal _cliffSeconds;

    /**
     * @notice Signer
     */
    address internal _signer;

    /**
     * @notice Claimed cumulative yield
     * @dev Only available after withdrawing vATH after yield pass expiry
     */
    uint256 internal _claimedCumulativeYield;

    /**
     * @notice Set of vesting order IDs
     */
    EnumerableSet.UintSet internal _orderIds;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice AethirYieldAdapter constructor
     */
    constructor(
        address yieldPass_,
        address aethirCheckerNodeLicense_,
        address aethirCheckerClaimAndWithdraw_
    ) EIP712(name(), DOMAIN_VERSION) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPass = yieldPass_;
        _aethirCheckerNodeLicense = aethirCheckerNodeLicense_;
        _aethirCheckerClaimAndWithdraw = ICheckerClaimAndWithdraw(aethirCheckerClaimAndWithdraw_);
        _athToken = IERC20(_aethirCheckerClaimAndWithdraw.aethirTokenAdress());
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice AethirYieldAdapter initializer
     */
    function initialize(uint48 cliffSeconds_, address signer_) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _cliffSeconds = cliffSeconds_;
        _signer = signer_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSE_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_PASS_ROLE, _yieldPass);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claim vATH
     * @param data Claim data
     * @return Yield amount
     */
    function _claimvATH(
        bytes memory data
    ) internal returns (uint256) {
        /* Decode claim data */
        AethirClaimData memory claimData = abi.decode(data, (AethirClaimData));

        /* Validate cliff seconds */
        if (claimData.cliffSeconds != _cliffSeconds) revert InvalidCliff();

        /* Claim vATH */
        _aethirCheckerClaimAndWithdraw.claim(
            claimData.orderId,
            claimData.cliffSeconds,
            claimData.expiryTimestamp,
            claimData.amount,
            claimData.signatureArray
        );

        /* Add yield amount */
        _claimedCumulativeYield += claimData.amount;

        /* Add order ID to set */
        _orderIds.add(claimData.orderId);

        return claimData.amount;
    }

    /**
     * @notice Withdraw ATH
     * @param data Withdraw data
     * @return Yield amount
     */
    function _withdrawATH(
        bytes memory data
    ) internal returns (uint256) {
        /* Decode withdraw data */
        AethirWithdrawData memory withdrawData = abi.decode(data, (AethirWithdrawData));

        /* Remove order IDs from set */
        for (uint256 i = 0; i < withdrawData.orderIdArray.length; i++) {
            _orderIds.remove(withdrawData.orderIdArray[i]);
        }

        /* Snapshot balance before */
        uint256 balanceBefore = _athToken.balanceOf(address(this));

        /* Withdraw ATH */
        _aethirCheckerClaimAndWithdraw.withdraw(
            withdrawData.orderIdArray, withdrawData.expiryTimestamp, withdrawData.signatureArray
        );

        /* Snapshot balance after */
        uint256 balanceAfter = _athToken.balanceOf(address(this));

        /* Compute yield amount */
        uint256 yieldAmount = balanceAfter - balanceBefore;

        return yieldAmount;
    }

    /**
     * @notice Validate signed nodes
     * @param tokenIds Token IDs
     * @param expiryTime Yield pass expiry timestamp
     * @param signedValidatedNodes Signed validated nodes
     * @return Burner wallet addresses
     */
    function _validateSignedNodes(
        uint256[] calldata tokenIds,
        uint64 expiryTime,
        SignedValidatedNodes memory signedValidatedNodes
    ) internal view returns (address[] memory) {
        ValidatedNodes memory nodes = signedValidatedNodes.nodes;

        /* Validate lengths */
        if (
            nodes.tokenIds.length != tokenIds.length || nodes.subscriptionExpiries.length != tokenIds.length
                || nodes.burnerWallets.length != tokenIds.length
        ) revert InvalidLength();

        /* Validate token IDs and compute encoded data */
        bytes memory encodedTokenIds;
        bytes memory encodedBurnerWallets;
        bytes memory encodedSubscriptionExpiries;
        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate token ID */
            if (nodes.tokenIds[i] != tokenIds[i]) revert InvalidTokenId();

            /* Validate expiry */
            if (nodes.subscriptionExpiries[i] < expiryTime) revert InvalidExpiry();

            /* Encode token ID */
            encodedTokenIds = bytes.concat(encodedTokenIds, abi.encode(nodes.tokenIds[i]));

            /* Encode burner wallet */
            encodedBurnerWallets = bytes.concat(encodedBurnerWallets, abi.encode(nodes.burnerWallets[i]));

            /* Encode subscription expiry */
            encodedSubscriptionExpiries =
                bytes.concat(encodedSubscriptionExpiries, abi.encode(nodes.subscriptionExpiries[i]));
        }

        /* Validate signature timestamp */
        if (nodes.timestamp > block.timestamp || nodes.timestamp + nodes.duration < block.timestamp) {
            revert InvalidTimestamp();
        }

        /* Recover nodes signer */
        address signerAddress = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        VALIDATED_NODES_TYPEHASH,
                        keccak256(encodedTokenIds),
                        keccak256(encodedBurnerWallets),
                        keccak256(encodedSubscriptionExpiries),
                        nodes.timestamp,
                        nodes.duration
                    )
                )
            ),
            signedValidatedNodes.signature
        );

        /* Validate signer */
        if (signerAddress != _signer) revert InvalidSignature();

        return nodes.burnerWallets;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function name() public pure returns (string memory) {
        return "Aethir Yield Adapter";
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function token() public view returns (address) {
        return address(_athToken);
    }

    /**
     * @inheritdoc IYieldAdapter
     * @dev Only available after withdrawing vATH after yield pass expiry
     */
    function cumulativeYield() public view returns (uint256) {
        return _claimedCumulativeYield;
    }

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPass() public view returns (address) {
        return _yieldPass;
    }

    /**
     * @notice Get Aethir Checker claim and withdraw
     * @return Checker claim and withdraw address
     */
    function aethirCheckerClaimAndWithdraw() public view returns (address) {
        return address(_aethirCheckerClaimAndWithdraw);
    }

    /**
     * @notice Get Aethir Checker node license
     * @return Checker node license address
     */
    function aethirCheckerNodeLicense() public view returns (address) {
        return address(_aethirCheckerNodeLicense);
    }

    /**
     * @notice Get cliff seconds
     * @return Cliff seconds
     */
    function cliffSeconds() public view returns (uint48) {
        return _cliffSeconds;
    }

    /**
     * @notice Get signer
     * @return Signer address
     */
    function signer() public view returns (address) {
        return _signer;
    }

    /**
     * @notice Get claim order IDs
     * @param offset Offset
     * @param count Count
     * @return Order IDs
     */
    function orderIds(uint256 offset, uint256 count) public view returns (uint256[] memory) {
        /* Clamp on count */
        count = Math.min(count, _orderIds.length() - offset);

        /* Create arrays */
        uint256[] memory ids = new uint256[](count);

        /* Cache end index */
        uint256 endIndex = offset + count;

        /* Fill array */
        for (uint256 i = offset; i < endIndex; i++) {
            ids[i - offset] = _orderIds.at(i);
        }

        return ids;
    }

    /*------------------------------------------------------------------------*/
    /* Yield Pass API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function setup(
        uint64 expiryTime,
        address account,
        uint256[] calldata tokenIds,
        bytes calldata setupData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address[] memory) {
        /* Decode setup data */
        SignedValidatedNodes memory signedValidatedNodes = abi.decode(setupData, (SignedValidatedNodes));

        /* Validate signed nodes */
        address[] memory burnerWallets = _validateSignedNodes(tokenIds, expiryTime, signedValidatedNodes);

        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer license NFT from account to yield adapter */
            IERC721(_aethirCheckerNodeLicense).safeTransferFrom(account, address(this), tokenIds[i]);

            /* Set user on license NFT */
            IERC4907(_aethirCheckerNodeLicense).setUser(tokenIds[i], burnerWallets[i], expiryTime);
        }

        return burnerWallets;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(
        uint64 expiryTime,
        bytes calldata harvestData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (uint256) {
        /* Skip if no data */
        if (harvestData.length == 0) return 0;

        /* Decode harvest data */
        (bool isClaim, bytes memory data) = abi.decode(harvestData, (bool, bytes));

        if (isClaim) {
            /* Claim vATH */
            _claimvATH(data);

            return 0;
        } else {
            /* Validate yield pass is expired */
            if (block.timestamp <= expiryTime) revert InvalidWindow();

            /* Withdraw ATH */
            return _withdrawATH(data);
        }
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claim(address recipient, uint256 amount) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Validate all claim order IDs have been processed for withdrawal */
        if (_orderIds.length() != 0) revert InvalidClaim();

        /* Transfer yield amount to recipient */
        if (amount > 0) _athToken.safeTransfer(recipient, amount);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function initiateWithdraw(
        uint64 expiryTime,
        uint256[] calldata
    ) external view onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Validate yield pass is expired */
        if (block.timestamp <= expiryTime) revert InvalidWindow();
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function withdraw(
        address recipient,
        uint256[] calldata tokenIds
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Transfer license NFT to recipient */
        for (uint256 i; i < tokenIds.length; i++) {
            IERC721(_aethirCheckerNodeLicense).transferFrom(address(this), recipient, tokenIds[i]);
        }
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Update cliff seconds
     * @param cliffSeconds_ Cliff seconds
     */
    function updateCliffSeconds(
        uint48 cliffSeconds_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _cliffSeconds = cliffSeconds_;

        /* Emit cliff seconds updated */
        emit CliffSecondsUpdated(cliffSeconds_);
    }

    /**
     * @notice Update signer
     * @param signer_ Signer address
     */
    function updateSigner(
        address signer_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _signer = signer_;

        /* Emit signer updated */
        emit SignerUpdated(signer_);
    }

    /**
     * @notice Pause the contract
     */
    function pause() public onlyRole(PAUSE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() public onlyRole(PAUSE_ADMIN_ROLE) {
        _unpause();
    }
}
