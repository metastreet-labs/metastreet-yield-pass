// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "./TestYieldToken.sol";

/**
 * @title Test Yield Adapter
 * @author MetaStreet Foundation
 */
contract TestYieldAdapter is IYieldAdapter, ERC721Holder, AccessControl {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /*------------------------------------------------------------------------*/
    /* Access Control Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass role
     */
    bytes32 public constant YIELD_PASS_ROLE = keccak256("YIELD_PASS_ROLE");

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
     * @notice Node License Token
     */
    IERC721 internal immutable _nodeLicenseToken;

    /**
     * @notice Yield token
     */
    IERC20 internal immutable _yieldToken;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Node license count
     */
    uint256 internal _nodeLicenseCount;

    /**
     * @notice Cumulative yield
     */
    uint256 internal _cumulativeYield;

    /**
     * @notice Last harvest time
     */
    uint64 internal _lastHarvestTimestamp;

    /**
     * @notice Withdrawal recipients (redemption hash to recipient)
     */
    mapping(bytes32 => address) internal _withdrawalRecipients;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice TestYieldAdapter constructor
     * @param yieldPassFactory_ Yield pass factory
     * @param expiryTime_ Expiry time
     * @param nodeLicenseToken_ Node License token
     * @param yieldToken_ Yield token
     */
    constructor(address yieldPassFactory_, uint64 expiryTime_, address nodeLicenseToken_, address yieldToken_) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPassFactory = yieldPassFactory_;
        _expiryTime = expiryTime_;
        _nodeLicenseToken = IERC721(nodeLicenseToken_);
        _yieldToken = IERC20(yieldToken_);
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice TestYieldAdapter initializer
     */
    function initialize() external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _lastHarvestTimestamp = uint64(block.timestamp);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_PASS_ROLE, _yieldPassFactory);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function name() public view returns (string memory) {
        return string.concat("Test Yield Adapter - Expiry: ", Strings.toString(_expiryTime));
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function token() public view returns (address) {
        return address(_yieldToken);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function cumulativeYield() public view returns (uint256) {
        return _cumulativeYield;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claimableYield() public view returns (uint256) {
        return _yieldToken.balanceOf(address(this));
    }

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPassFactory() public view returns (address) {
        return _yieldPassFactory;
    }

    /**
     * @notice Get node license token
     * @return Node license token
     */
    function nodeLicenseToken() public view returns (address) {
        return address(_nodeLicenseToken);
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
        bytes calldata
    ) external onlyRole(YIELD_PASS_ROLE) returns (address[] memory) {
        /* Transfer node licenses from account */
        for (uint256 i; i < tokenIds.length; i++) {
            _nodeLicenseToken.safeTransferFrom(account, address(this), tokenIds[i]);
        }

        /* Update node license count */
        _nodeLicenseCount += tokenIds.length;

        /* Return this contract as operator */
        address[] memory operators = new address[](1);
        operators[0] = address(this);

        return operators;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(
        bytes calldata
    ) external onlyRole(YIELD_PASS_ROLE) returns (uint256) {
        /* Validate final harvest hasn't occurred */
        if (_lastHarvestTimestamp > _expiryTime) revert HarvestCompleted();

        /* Compute random yield at a rate of about 1.0-1.5 ether per node license per day */
        uint256 prng = uint256(keccak256(abi.encodePacked(block.number, block.timestamp, _lastHarvestTimestamp)));
        uint256 yieldRate = ((1 ether + (prng % 0.5 ether)) * _nodeLicenseCount) / 86400;
        uint256 yieldAmount = yieldRate * (block.timestamp - _lastHarvestTimestamp);

        /* "Claim" yield */
        TestYieldToken(address(_yieldToken)).mint(address(this), yieldAmount);

        _cumulativeYield += yieldAmount;
        _lastHarvestTimestamp = uint64(block.timestamp);

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claim(address recipient, uint256 amount) external onlyRole(YIELD_PASS_ROLE) {
        /* Validate harvest is completed */
        if (_lastHarvestTimestamp < _expiryTime) revert HarvestNotCompleted();

        /* Transfer yield amount to recipient */
        _yieldToken.safeTransfer(recipient, amount);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function redeem(address recipient, uint256[] calldata, bytes32 redemptionHash) external onlyRole(YIELD_PASS_ROLE) {
        /* Set withdrawal recipient */
        _withdrawalRecipients[redemptionHash] = recipient;
    }

    /**
     * @inheritdoc IYieldAdapter
     * @dev Transfer keys by pool for gas optimization.
     */
    function withdraw(
        uint256[] calldata tokenIds,
        bytes32 redemptionHash
    ) external onlyRole(YIELD_PASS_ROLE) returns (address) {
        /* Get recipient */
        address recipient = _withdrawalRecipients[redemptionHash];

        /* Validate recipient is set */
        if (recipient == address(0)) revert InvalidRecipient();

        /* Delete withdrawal recipient */
        delete _withdrawalRecipients[redemptionHash];

        /* Transfer node licenses to recipient */
        for (uint256 i; i < tokenIds.length; i++) {
            _nodeLicenseToken.safeTransferFrom(address(this), recipient, tokenIds[i]);
        }

        /* Update node license count */
        _nodeLicenseCount -= tokenIds.length;

        return recipient;
    }
}
