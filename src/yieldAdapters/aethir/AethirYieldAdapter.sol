// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

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
    function withdraw(uint256[] memory orderIdArray, uint48 expiryTimestamp, bytes[] memory signatureArray) external;
    function claim(
        uint256 orderId,
        uint48 cliffSeconds,
        uint48 expiryTimestamp,
        uint256 amount,
        bytes[] memory signatureArray
    ) external;
}

/**
 * @title Aethir Yield Adapter
 * @author MetaStreet Foundation
 */
contract AethirYieldAdapter is IYieldAdapter, ERC721Holder, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Error */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid token owner
     */
    error InvalidOwner();

    /**
     * @notice Unsupported operator
     */
    error UnsupportedOperator();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Invalid cliff seconds
     */
    error InvalidCliff();

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

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Operator added
     * @param operator Operator address
     */
    event OperatorAdded(address indexed operator);

    /**
     * @notice Operator removed
     * @param operator Operator address
     */
    event OperatorRemoved(address indexed operator);

    /**
     * @notice Cliff seconds updated
     * @param cliffSeconds Cliff seconds
     */
    event CliffSecondsUpdated(uint48 cliffSeconds);

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
     * @notice Set of order IDs
     */
    EnumerableSet.UintSet internal _orderIds;

    /**
     * @notice Set of allowed operators
     */
    EnumerableSet.AddressSet internal _allowedOperators;

    /**
     * @notice Set of interacted operators
     */
    EnumerableSet.AddressSet internal _interactedOperators;

    /**
     * @notice Mapping of tokenId to operator
     */
    mapping(uint256 => address) internal _operators;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldAdapter constructor
     */
    constructor(address yieldPass_, address checkerNodeLicense_, address checkerClaimAndWithdraw_, address athToken_) {
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
    function initialize(uint48 cliffSeconds_, address[] memory operators_) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _cliffSeconds = cliffSeconds_;

        for (uint256 i = 0; i < operators_.length; i++) {
            /* Add operator to allowlist */
            _allowedOperators.add(operators_[i]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_PASS_ROLE, _yieldPass);
    }

    /*------------------------------------------------------------------------*/
    /* Internal Helpers */
    /*------------------------------------------------------------------------*/

    function _claim(bytes memory data) internal {
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
    }

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

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

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
     */
    function tokenDelegatee(uint256 tokenId) public view returns (address) {
        return _operators[tokenId];
    }

    /**
     * @inheritdoc IYieldAdapter
     * @dev Only available after claiming vATH after yield pass expiry
     */
    function cumulativeYield() public view returns (uint256) {
        return _cumulativeYieldAmount;
    }

    /**
     * @notice Get operator factory
     * @return Operator factory address
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
     * @notice Get allowed operators
     * @return Allowed operators
     */
    function allowedOperators() public view returns (address[] memory) {
        return _allowedOperators.values();
    }

    /**
     * @notice Get interacted operators
     * @return Interacted operators
     */
    function interactedOperators() public view returns (address[] memory) {
        return _interactedOperators.values();
    }

    /**
     * @notice Get cliff seconds
     * @return Cliff seconds
     */
    function cliffSeconds() public view returns (uint48) {
        return _cliffSeconds;
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
        address,
        address,
        bytes calldata setupData
    ) external onlyRole(YIELD_PASS_ROLE) {
        /* Validate this contract owns token ID */
        if (IERC721(_checkerNodeLicense).ownerOf(tokenId) != address(this)) revert InvalidOwner();

        /* Decode setup data */
        address operator = abi.decode(setupData, (address));

        /* Validate operator is allowed */
        if (!_allowedOperators.contains(operator)) revert UnsupportedOperator();

        /* Add operator to interacted operators */
        _interactedOperators.add(operator);

        /* Delegate license */
        IERC4907(_checkerNodeLicense).setUser(tokenId, operator, expiry);

        /* Store operator */
        _operators[tokenId] = operator;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function validateClaim(address) external view returns (bool) {
        /* Validate all order IDs have been processed for withdrawal */
        return _orderIds.length() == 0;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(uint64 expiry, bytes calldata harvestData) external onlyRole(YIELD_PASS_ROLE) returns (uint256) {
        /* Skip if no data */
        if (harvestData.length == 0) return 0;

        /* Decode harvest data */
        (bool isClaim, bytes memory data) = abi.decode(harvestData, (bool, bytes));

        if (isClaim) {
            /* Claim vATH */
            _claim(data);

            return 0;
        }

        /* Validate expiry is in the past for withdrawal */
        if (block.timestamp <= expiry) revert InvalidWindow();

        /* Withdraw ATH */
        return _withdraw(data);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function initiateTeardown(uint256, uint64 expiry) external view onlyRole(YIELD_PASS_ROLE) returns (bytes memory) {
        /* Validate expiry is in the past */
        if (block.timestamp <= expiry) revert InvalidWindow();

        return "";
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function teardown(uint256 tokenId, address receiver, bytes calldata) external onlyRole(YIELD_PASS_ROLE) {
        /* Remove token ID to operator from mapping */
        delete _operators[tokenId];

        /* Transfer key to receiver */
        IERC721(_checkerNodeLicense).transferFrom(address(this), receiver, tokenId);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add or remove operator from whitelist
     * @param operator Operator to add or remove
     */
    function updateOperators(address operator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate operator is allowed */
        if (_allowedOperators.contains(operator)) {
            _allowedOperators.remove(operator);

            /* Emit operator removed */
            emit OperatorRemoved(operator);
        } else {
            _allowedOperators.add(operator);

            /* Emit operator added */
            emit OperatorAdded(operator);
        }
    }

    /**
     * @notice Update cliff seconds
     * @param cliffSeconds_ Cliff seconds
     */
    function updateCliffSeconds(uint48 cliffSeconds_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _cliffSeconds = cliffSeconds_;

        /* Emit cliff seconds updated */
        emit CliffSecondsUpdated(cliffSeconds_);
    }
}
