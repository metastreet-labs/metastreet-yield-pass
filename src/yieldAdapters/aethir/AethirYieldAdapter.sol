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
import "@openzeppelin/contracts/utils/Strings.sol";

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
    string public constant IMPLEMENTATION_VERSION = "1.2";

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
     * @notice Invalid cliff seconds
     */
    error InvalidCliff();

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

    /**
     * @notice License transfer unlocked
     * @param isLicenseTransferUnlocked New license transfer unlocked status
     */
    event LicenseTransferUnlocked(bool isLicenseTransferUnlocked);

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
     * @notice Yield pass factory
     */
    address internal immutable _yieldPassFactory;

    /**
     * @notice Expiry time
     */
    uint64 internal immutable _expiryTime;

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

    /**
     * @notice Withdrawal recipients (redemption hash to recipient)
     */
    mapping(bytes32 => address) internal _withdrawalRecipients;

    /**
     * @notice License transfer unlocked
     */
    bool internal _isLicenseTransferUnlocked;

    /**
     * @notice License original owners (token ID to owner)
     */
    mapping(uint256 => address) internal _licenseOriginalOwners;

    /**
     * @notice Final harvest completed
     */
    bool internal _harvestCompleted;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice AethirYieldAdapter constructor
     * @param yieldPassFactory_ Yield pass factory
     * @param expiryTime_ Expiry time
     * @param aethirCheckerNodeLicense_ Aethir checker node license token
     * @param aethirCheckerClaimAndWithdraw_ Aethir checker claim and withdraw address
     */
    constructor(
        address yieldPassFactory_,
        uint64 expiryTime_,
        address aethirCheckerNodeLicense_,
        address aethirCheckerClaimAndWithdraw_
    ) EIP712("Aethir Yield Adapter", DOMAIN_VERSION) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPassFactory = yieldPassFactory_;
        _expiryTime = expiryTime_;
        _aethirCheckerNodeLicense = aethirCheckerNodeLicense_;
        _aethirCheckerClaimAndWithdraw = ICheckerClaimAndWithdraw(aethirCheckerClaimAndWithdraw_);
        _athToken = IERC20(_aethirCheckerClaimAndWithdraw.aethirTokenAdress());
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice AethirYieldAdapter initializer
     * @param cliffSeconds_ Cliff seconds
     * @param signer_ Signer
     * @param isLicenseTransferUnlocked_ License transfer unlocked
     */
    function initialize(uint48 cliffSeconds_, address signer_, bool isLicenseTransferUnlocked_) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _cliffSeconds = cliffSeconds_;
        _signer = signer_;
        _isLicenseTransferUnlocked = isLicenseTransferUnlocked_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSE_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Modifier that throws if caller is not yield pass factory
     */
    modifier onlyYieldPassFactory() {
        require(msg.sender == _yieldPassFactory, "Unauthorized caller");
        _;
    }

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
        uint64 expiryTime,
        uint256[] calldata tokenIds,
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
    function name() public view returns (string memory) {
        return string.concat("Aethir Yield Adapter - Expiry: ", Strings.toString(_expiryTime));
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
     * @inheritdoc IYieldAdapter
     */
    function claimableYield() public view returns (uint256) {
        return _athToken.balanceOf(address(this));
    }

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPassFactory() public view returns (address) {
        return _yieldPassFactory;
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
        address account,
        uint256[] calldata tokenIds,
        bytes calldata setupData
    ) external onlyYieldPassFactory whenNotPaused returns (address[] memory) {
        /* Decode setup data */
        SignedValidatedNodes memory signedValidatedNodes = abi.decode(setupData, (SignedValidatedNodes));

        /* Validate signed nodes */
        address[] memory burnerWallets = _validateSignedNodes(_expiryTime, tokenIds, signedValidatedNodes);

        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer license NFT from account to yield adapter */
            IERC721(_aethirCheckerNodeLicense).safeTransferFrom(account, address(this), tokenIds[i]);

            /* Set user on license NFT */
            IERC4907(_aethirCheckerNodeLicense).setUser(tokenIds[i], burnerWallets[i], _expiryTime);

            /* Set original owner */
            _licenseOriginalOwners[tokenIds[i]] = account;
        }

        return burnerWallets;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(
        bytes calldata harvestData
    ) external onlyYieldPassFactory whenNotPaused returns (uint256) {
        /* Skip if no data */
        if (harvestData.length == 0) return 0;

        /* Decode harvest data */
        (bool isClaim, bytes memory data) = abi.decode(harvestData, (bool, bytes));

        if (isClaim) {
            /* Validate final harvest hasn't occurred */
            if (_harvestCompleted) revert HarvestCompleted();

            /* Set harvest completed for last claim after expiry */
            if (block.timestamp > _expiryTime) _harvestCompleted = true;

            /* Claim vATH */
            _claimvATH(data);

            return 0;
        } else {
            /* Withdraw ATH */
            return _withdrawATH(data);
        }
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claim(address recipient, uint256 amount) external onlyYieldPassFactory whenNotPaused {
        /* Validate harvest is completed */
        if (!_harvestCompleted) revert HarvestNotCompleted();

        /* Transfer yield amount to recipient */
        _athToken.safeTransfer(recipient, amount);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function redeem(
        address recipient,
        uint256[] calldata tokenIds,
        bytes32 redemptionHash
    ) external onlyYieldPassFactory whenNotPaused {
        /* Validate recipient if transfer is not unlocked */
        if (!_isLicenseTransferUnlocked) {
            for (uint256 i; i < tokenIds.length; i++) {
                if (_licenseOriginalOwners[tokenIds[i]] != recipient) revert InvalidRecipient();
            }
        }

        /* Set withdrawal recipient */
        _withdrawalRecipients[redemptionHash] = recipient;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function withdraw(
        uint256[] calldata tokenIds,
        bytes32 redemptionHash
    ) external onlyYieldPassFactory whenNotPaused returns (address) {
        /* Get recipient */
        address recipient = _withdrawalRecipients[redemptionHash];

        /* Validate recipient */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Delete withdrawal recipient */
        delete _withdrawalRecipients[redemptionHash];

        /* Withdraw license NFTs */
        for (uint256 i; i < tokenIds.length; i++) {
            /* Delete original owner */
            delete _licenseOriginalOwners[tokenIds[i]];

            /* Transfer license NFT to recipient */
            IERC721(_aethirCheckerNodeLicense).transferFrom(address(this), recipient, tokenIds[i]);
        }

        return recipient;
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
     * @notice Set license transfer unlocked
     * @param isLicenseTransferUnlocked_ Transfer unlocked
     */
    function setLicenseTransferUnlocked(
        bool isLicenseTransferUnlocked_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _isLicenseTransferUnlocked = isLicenseTransferUnlocked_;

        emit LicenseTransferUnlocked(isLicenseTransferUnlocked_);
    }

    /**
     * @notice Set license original owners
     * @dev Temporary admin function to facilitate v1.0 -> v1.1 upgrade
     * @param tokenIds Token IDs
     * @param owners Owners
     */
    function setLicenseOriginalOwners(
        uint256[] calldata tokenIds,
        address[] calldata owners
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate lengths */
        if (tokenIds.length != owners.length) revert InvalidLength();

        /* Update original owners */
        for (uint256 i; i < tokenIds.length; i++) {
            _licenseOriginalOwners[tokenIds[i]] = owners[i];
        }
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

    /**
     * @notice Redelegate token IDs
     * @param tokenIds Token IDs
     * @param burnerWallets Burner wallet addresses
     * @param subscriptionExpiries Subscription expiry timestamps
     */
    function redelegate(
        uint256[] calldata tokenIds,
        address[] calldata burnerWallets,
        uint64[] calldata subscriptionExpiries
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate lengths */
        if (tokenIds.length != burnerWallets.length || tokenIds.length != subscriptionExpiries.length) {
            revert InvalidLength();
        }

        for (uint256 i; i < tokenIds.length; i++) {
            /* Validate token ID is owned by yield adapter */
            if (IERC721(_aethirCheckerNodeLicense).ownerOf(tokenIds[i]) != address(this)) revert InvalidTokenId();

            /* Set user on license NFT */
            IERC4907(_aethirCheckerNodeLicense).setUser(tokenIds[i], burnerWallets[i], subscriptionExpiries[i]);
        }
    }
}
