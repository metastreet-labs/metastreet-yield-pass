// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

import "forge-std/console.sol";

/**
 * @title IGuardianDelegationProxy Interface
 */
interface IGuardianDelegationProxy {
    enum DelegationType {
        Undefined,
        Validator,
        LightNode
    }

    function delegateToLightNodes(
        address[] memory receivers,
        uint256[] memory maxAmounts,
        bool partialFill
    ) external returns (uint256 delegations, uint256 totalDesired);
    function balanceOfSent(address sender, DelegationType delegationType) external view returns (uint256);
    function guardianNFT() external view returns (IERC721);
    function hasSent(
        address sender
    ) external view returns (bool);
    function implementation() external view returns (address);
    function replaceImplementation(address newImplementation, bytes memory data) external;
}

/**
 * @title GuardianNFT Interface
 */
interface IGuardianNFT {
    // function batchTransferFrom(address from, address to, uint256[] memory tokenIds) external;
    function safeTransferFromWithDedelegate(address from, address to, uint256 tokenId) external;
}

/**
 * @title Sophon Yield Adapter
 * @author MetaStreet Foundation
 */
contract SophonYieldAdapter is IYieldAdapter, ERC721Holder, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

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

    /**
     * @notice Pause admin role
     */
    bytes32 public constant PAUSE_ADMIN_ROLE = keccak256("PAUSE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid token ids
     */
    error InvalidTokenIds();

    /**
     * @notice Invalid setup data
     */
    error InvalidSetupData();

    /**
     * @notice Invalid validator delegations
     */
    error InvalidValidatorDelegations();

    /**
     * @notice Unsupported light node
     */
    error UnsupportedLightNode();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Not implemented
     */
    error NotImplemented();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Light node added
     * @param lightNode Light node address
     */
    event LightNodeAdded(address indexed lightNode);

    /**
     * @notice Light node removed
     * @param lightNode Light node address
     */
    event LightNodeRemoved(address indexed lightNode);

    /**
     * @notice Transfer unlocked
     * @param isTransferUnlocked Transfer unlocked
     */
    event TransferUnlocked(bool indexed isTransferUnlocked);

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass
     */
    address internal immutable _yieldPass;

    /**
     * @notice Yield pass expiry
     */
    uint64 internal immutable _yieldPassExpiry;

    /**
     * @notice SOPHON token
     */
    IERC20 internal immutable _sophonToken;

    /**
     * @notice SOPHON node license
     */
    IGuardianNFT internal immutable _sophonNodeLicense;

    /**
     * @notice Guardian delegation
     */
    IGuardianDelegationProxy internal immutable _guardianDelegation;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Transfer unlocked
     */
    bool internal _isTransferUnlocked;

    /**
     * @notice Original owners (token ID to owner)
     */
    mapping(uint256 => address) internal _originalOwners;

    /**
     * @notice Withdrawal recipients (redemption hash to recipient)
     */
    mapping(bytes32 => address) internal _withdrawalRecipients;

    /**
     * @notice Assigned light nodes (token ID to light node)
     */
    mapping(uint256 => address) internal _assignedLightNodes;

    /**
     * @notice Set of all light nodes (superset of _allowedLightNodes)
     */
    EnumerableSet.AddressSet private _allLightNodes;

    /**
     * @notice Set of allowed light nodes
     */
    EnumerableSet.AddressSet private _allowedLightNodes;

    /**
     * @notice Gap for future upgrades
     */
    uint256[49] __gap;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice SophonYieldAdapter constructor
     */
    constructor(address yieldPass_, uint64 yieldPassExpiry_, address guardianDelegation_, address sophonToken_) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPass = yieldPass_;
        _yieldPassExpiry = yieldPassExpiry_;
        _guardianDelegation = IGuardianDelegationProxy(guardianDelegation_);
        _sophonNodeLicense = IGuardianNFT(address(_guardianDelegation.guardianNFT()));
        _sophonToken = IERC20(sophonToken_);
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice SophonYieldAdapter initializer
     * @param lightNodes_ Light nodes to add
     * @param isTransferUnlocked_ Transfer unlocked
     */
    function initialize(address[] memory lightNodes_, bool isTransferUnlocked_) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        _isTransferUnlocked = isTransferUnlocked_;

        for (uint256 i; i < lightNodes_.length; i++) {
            /* Add pool to allowlist */
            _allowedLightNodes.add(lightNodes_[i]);

            /* Add pool to all lightNodes */
            _allLightNodes.add(lightNodes_[i]);
        }

        _grantRole(YIELD_PASS_ROLE, _yieldPass);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSE_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function name() public pure returns (string memory) {
        return "Sophon Yield Adapter";
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function token() public view returns (address) {
        return address(_sophonToken);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function cumulativeYield() public pure returns (uint256) {
        return 0;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claimableYield() external view returns (uint256) {
        return _sophonToken.balanceOf(address(this));
    }

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPass() public view returns (address) {
        return _yieldPass;
    }

    /**
     * @notice Get Guardian delegation
     * @return Guardian delegation address
     */
    function guardianDelegation() public view returns (address) {
        return address(_guardianDelegation);
    }

    /**
     * @notice Get SOPHON node license
     * @return Node license address
     */
    function sophonNodeLicense() public view returns (address) {
        return address(_sophonNodeLicense);
    }

    /**
     * @notice Get allowed lightNodes
     * @return Allowed lightNodes
     */
    function allowedPools() public view returns (address[] memory) {
        return _allowedLightNodes.values();
    }

    /**
     * @notice Get all lightNodes
     * @return All lightNodes
     */
    function allPools() public view returns (address[] memory) {
        return _allLightNodes.values();
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
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address[] memory) {
        /* Decode setup data */
        (address[] memory lightNodes, uint256[] memory quantities) = abi.decode(setupData, (address[], uint256[]));

        /* Validate quantities */
        if (quantities.length != lightNodes.length) revert InvalidSetupData();

        /* Validate current validator delegations */
        if (
            _guardianDelegation.balanceOfSent(account, IGuardianDelegationProxy.DelegationType.Validator)
                < tokenIds.length
        ) revert InvalidValidatorDelegations();

        uint256 total;
        for (uint256 i; i < lightNodes.length; i++) {
            /* Validate pool is allowed */
            if (!_allowedLightNodes.contains(lightNodes[i])) revert UnsupportedLightNode();

            /* Increment total*/
            total += quantities[i];
        }

        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer licenses */
            _sophonNodeLicense.safeTransferFromWithDedelegate(account, address(this), tokenIds[i]);

            _originalOwners[tokenIds[i]] = account;
        }

        /* Validate total quantities */
        if (total != tokenIds.length) revert InvalidSetupData();

        /* Delegate to light node */
        _guardianDelegation.delegateToLightNodes(lightNodes, quantities, false);

        return lightNodes;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(
        bytes calldata
    ) external view onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (uint256) {
        revert NotImplemented();
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claim(address, uint256) external view onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        revert NotImplemented();
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function redeem(address, uint256[] calldata, bytes32) external view onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        revert NotImplemented();
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function withdraw(
        uint256[] calldata,
        bytes32
    ) external view onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address) {
        revert NotImplemented();
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add light nodes to allowlist
     * @param lightNodes Light nodes to add
     */
    function addLightNodes(
        address[] memory lightNodes
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < lightNodes.length; i++) {
            /* Add light node to allowed light nodes */
            _allowedLightNodes.add(lightNodes[i]);

            /* Add light node to all light nodes */
            _allLightNodes.add(lightNodes[i]);

            emit LightNodeAdded(lightNodes[i]);
        }
    }

    /**
     * @notice Remove light nodes from allowlist
     * @param lightNodes Light nodes to remove
     */
    function removeLightNodes(
        address[] memory lightNodes
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < lightNodes.length; i++) {
            /* Remove light node from allowed light nodes */
            _allowedLightNodes.remove(lightNodes[i]);

            emit LightNodeRemoved(lightNodes[i]);
        }
    }

    /**
     * @notice Unlock transfer
     * @param isTransferUnlocked_ Transfer unlocked
     */
    function unlockTransfer(
        bool isTransferUnlocked_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _isTransferUnlocked = isTransferUnlocked_;

        emit TransferUnlocked(isTransferUnlocked_);
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
