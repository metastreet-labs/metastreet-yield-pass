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
import {IYieldPass} from "src/interfaces/IYieldPass.sol";

interface IERC4907 {
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    function setUser(uint256 tokenId, address user, uint64 expires) external;
    function userOf(uint256 tokenId) external view returns (address);
    function userExpires(uint256 tokenId) external view returns (uint256);
}

/**
 * @title Aethir Checker Claim And Withdraw Interface
 */
interface ICheckerClaimAndWithdraw {
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
     * @notice Node EIP-712 typehash
     */
    bytes32 public constant NODE_TYPEHASH =
        keccak256("Node(address user,uint256 tokenId,address burnerWallet,uint64 timestamp,uint64 duration)");

    /*------------------------------------------------------------------------*/
    /* Error */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid token owner
     */
    error InvalidOwner();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Invalid cliff seconds
     */
    error InvalidCliff();

    /**
     * @notice Invalid sender
     */
    error InvalidUser();

    /**
     * @notice Invalid token ID
     */
    error InvalidTokenId();

    /**
     * @notice Invalid timestamp
     */
    error InvalidTimestamp();

    /**
     * @notice Invalid signature
     */
    error InvalidSignature();

    /*------------------------------------------------------------------------*/
    /* Access Control Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass role
     */
    bytes32 public constant YIELD_PASS_ROLE = keccak256("YIELD_PASS_ROLE");

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claim data
     * @param orderId Order ID
     * @param cliffSeconds Cliff period in seconds
     * @param expiryTimestamp Expiry timestamp
     * @param amount Amount to claim
     * @param signatureArray Array of signatures
     */
    struct ClaimData {
        uint256 orderId;
        uint48 cliffSeconds;
        uint48 expiryTimestamp;
        uint256 amount;
        bytes[] signatureArray;
    }

    /**
     * @notice Withdraw data
     * @param orderIdArray Array of order IDs
     * @param expiryTimestamp Expiry timestamp
     * @param signatureArray Array of signatures
     */
    struct WithdrawData {
        uint256[] orderIdArray;
        uint48 expiryTimestamp;
        bytes[] signatureArray;
    }

    /**
     * @notice Node
     * @param user User address
     * @param tokenId Token ID
     * @param burnerWallet Burner wallet address
     * @param timestamp Timestamp
     * @param duration Duration validity
     */
    struct ValidatedNode {
        address user;
        uint256 tokenId;
        address burnerWallet;
        uint64 timestamp;
        uint64 duration;
    }

    /**
     * @notice Validated node with signature
     * @param node Validated node
     * @param signature ECDSA signature
     */
    struct SignedNode {
        ValidatedNode node;
        bytes signature;
    }

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Cliff seconds updated
     * @param cliffSeconds Cliff seconds
     */
    event CliffSecondsUpdated(uint48 cliffSeconds);

    /**
     * @notice Signer updated
     * @param signer Signer address
     */
    event SignerUpdated(address signer);

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass
     */
    address internal immutable _yieldPass;

    /**
     * @notice Checker node license
     */
    address internal immutable _checkerNodeLicense;

    /**
     * @notice Checker claim and withdraw
     */
    ICheckerClaimAndWithdraw internal immutable _checkerClaimAndWithdraw;

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
     * @notice Cumulative yield amount
     * @dev Only available after claiming vATH after yield pass expiry
     */
    uint256 internal _cumulativeYieldAmount;

    /**
     * @notice Cliff seconds
     */
    uint48 internal _cliffSeconds;

    /**
     * @notice Signer
     */
    address internal _signer;

    /**
     * @notice Set of order IDs
     */
    EnumerableSet.UintSet internal _orderIds;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldAdapter constructor
     */
    constructor(
        string memory name_,
        address yieldPass_,
        address checkerNodeLicense_,
        address checkerClaimAndWithdraw_,
        address athToken_
    ) EIP712(name_, DOMAIN_VERSION()) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPass = yieldPass_;
        _checkerNodeLicense = checkerNodeLicense_;
        _checkerClaimAndWithdraw = ICheckerClaimAndWithdraw(checkerClaimAndWithdraw_);
        _athToken = IERC20(athToken_);
    }

    /*------------------------------------------------------------------------*/
    /* Intialized */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize
     */
    function initialize(uint48 cliffSeconds_, address signer_) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _cliffSeconds = cliffSeconds_;

        _signer = signer_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    function _claim(bytes memory data) internal returns (uint256) {
        /* Decode harvest data */
        ClaimData[] memory claimData = abi.decode(data, (ClaimData[]));

        /* Claim vATH */
        uint256 yieldAmount;
        for (uint256 i = 0; i < claimData.length; i++) {
            /* Validate cliff seconds */
            if (claimData[i].cliffSeconds != _cliffSeconds) revert InvalidCliff();

            _checkerClaimAndWithdraw.claim(
                claimData[i].orderId,
                claimData[i].cliffSeconds,
                claimData[i].expiryTimestamp,
                claimData[i].amount,
                claimData[i].signatureArray
            );

            /* Add yield amount */
            yieldAmount += claimData[i].amount;

            /* Add order ID to set */
            _orderIds.add(claimData[i].orderId);
        }

        _cumulativeYieldAmount += yieldAmount;

        return yieldAmount;
    }

    /**
     * @notice Withdraw ATH
     * @param data Withdraw data
     * @return Yield amount
     */
    function _withdraw(bytes memory data) internal returns (uint256) {
        /* Decode harvest data */
        WithdrawData memory withdrawData = abi.decode(data, (WithdrawData));

        /* Remove order IDs from set */
        for (uint256 i = 0; i < withdrawData.orderIdArray.length; i++) {
            _orderIds.remove(withdrawData.orderIdArray[i]);
        }

        /* Snapshot balance before */
        uint256 balanceBefore = _athToken.balanceOf(address(this));

        /* Withdraw ATH */
        _checkerClaimAndWithdraw.withdraw(
            withdrawData.orderIdArray, withdrawData.expiryTimestamp, withdrawData.signatureArray
        );

        /* Snapshot balance after */
        uint256 balanceAfter = _athToken.balanceOf(address(this));

        /* Compute yield amount */
        uint256 yieldAmount = balanceAfter - balanceBefore;

        /* Transfer yield amount to yield pass contract */
        if (yieldAmount > 0) _athToken.safeTransfer(_yieldPass, yieldAmount);

        return yieldAmount;
    }

    /**
     * @notice Validate signed node
     * @param user User address
     * @param tokenId Token ID
     * @param signedNode Signed node
     * @return Burner wallet address
     */
    function _validateSignedNode(
        address user,
        uint256 tokenId,
        SignedNode memory signedNode
    ) internal view returns (address) {
        ValidatedNode memory node = signedNode.node;

        /* Validate user */
        if (node.user != user) revert InvalidUser();

        /* Validate token ID */
        if (node.tokenId != tokenId) revert InvalidTokenId();

        /* Validate timestamp is in the past and expiry is in the future */
        if (node.timestamp > block.timestamp || node.timestamp + node.duration < block.timestamp) {
            revert InvalidTimestamp();
        }

        /* Recover node signer */
        address signerAddress = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(NODE_TYPEHASH, node.user, node.tokenId, node.burnerWallet, node.timestamp, node.duration)
                )
            ),
            signedNode.signature
        );

        /* Validate signer */
        if (signerAddress != _signer) revert InvalidSignature();

        return node.burnerWallet;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get Aethir yield adapter implementation version
     * @return Aethir yield adapter implementation version
     */
    function IMPLEMENTATION_VERSION() public pure returns (string memory) {
        return "1.0";
    }

    /**
     * @notice Get signing domain version
     * @return Signing domain version
     */
    function DOMAIN_VERSION() public pure returns (string memory) {
        return "1.0";
    }

    /**
     * @notice Get yield pass
     * @return Yield pass address
     */
    function yieldPass() public view returns (address) {
        return _yieldPass;
    }

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
     * @dev Only available after claiming vATH after yield pass expiry
     */
    function cumulativeYield() public view returns (uint256) {
        return _cumulativeYieldAmount;
    }

    /**
     * @notice Get checker factory
     * @return Checker factory address
     */
    function checkerClaimAndWithdraw() public view returns (address) {
        return address(_checkerClaimAndWithdraw);
    }

    /**
     * @notice Get checker node license
     * @return Checker node license address
     */
    function license() public view returns (address) {
        return address(_checkerNodeLicense);
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
        uint256 tokenId,
        uint64 expiry,
        address minter,
        address,
        bytes calldata setupData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address) {
        /* Validate this contract owns token ID */
        if (IERC721(_checkerNodeLicense).ownerOf(tokenId) != address(this)) revert InvalidOwner();

        /* Decode setup data */
        SignedNode memory signedNode = abi.decode(setupData, (SignedNode));

        /* Validate signed node */
        address burnerWallet = _validateSignedNode(minter, tokenId, signedNode);

        /* Set user on license NFT */
        IERC4907(_checkerNodeLicense).setUser(tokenId, burnerWallet, expiry);

        return burnerWallet;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function validateClaim(address) external view whenNotPaused returns (bool) {
        /* Validate all order IDs have been processed for withdrawal */
        return _orderIds.length() == 0;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(
        uint64 expiry,
        bytes calldata harvestData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (uint256) {
        /* Skip if no data */
        if (harvestData.length == 0) return 0;

        /* Decode harvest data */
        (bool isClaim, bytes memory data) = abi.decode(harvestData, (bool, bytes));

        if (isClaim) {
            /* Claim vATH */
            _claim(data);

            return 0;
        } else {
            /* Validate expiry is in the past for withdrawal */
            if (block.timestamp <= expiry) revert InvalidWindow();

            /* Withdraw ATH */
            return _withdraw(data);
        }
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function initiateTeardown(
        uint256,
        uint64 expiry
    ) external view whenNotPaused onlyRole(YIELD_PASS_ROLE) returns (bytes memory) {
        /* Validate expiry is in the past */
        if (block.timestamp <= expiry) revert InvalidWindow();

        return "";
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function teardown(
        uint256 tokenId,
        address receiver,
        bytes calldata
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Transfer key to receiver */
        IERC721(_checkerNodeLicense).transferFrom(address(this), receiver, tokenId);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Update cliff seconds
     * @param cliffSeconds_ Cliff seconds
     */
    function updateCliffSeconds(uint48 cliffSeconds_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _cliffSeconds = cliffSeconds_;

        /* Emit cliff seconds updated */
        emit CliffSecondsUpdated(cliffSeconds_);
    }

    /**
     * @notice Update signer
     * @param signer_ Signer address
     */
    function updateSigner(address signer_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _signer = signer_;

        /* Emit signer updated */
        emit SignerUpdated(signer_);
    }

    /**
     * @notice Pause the contract
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
