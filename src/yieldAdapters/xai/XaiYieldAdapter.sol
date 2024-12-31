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

/**
 * @title XAI Pool Factory Interface
 */
interface IPoolFactory {
    function nodeLicenseAddress() external returns (address);
    function esXaiAddress() external returns (address);
    function refereeAddress() external returns (address);
    function stakeKeys(address pool, uint256 keyAmount) external;
    function unstakeKeys(address pool, uint256 unstakeRequestIndex) external;
    function claimFromPools(
        address[] memory pools
    ) external;
}

/**
 * @title XAI Pool Interface
 */
interface IPool {
    function keyBucket() external view returns (IBucketTracker);
}

/**
 * @title XAI Bucket Tracker Interface
 */
interface IBucketTracker {
    function accumulativeDividendOf(
        address account
    ) external view returns (uint256);
}

/**
 * @title XAI Referee Interface
 */
interface IReferee {
    function isKycApproved(
        address wallet
    ) external view returns (bool);
}

/**
 * @title XAI Node License Interface
 */
interface INodeLicense {
    function transferStakedKeys(address from, address to, address poolAddress, uint256[] memory tokenIds) external;
}

/**
 * @title XAI Yield Adapter
 * @author MetaStreet Foundation
 */
contract XaiYieldAdapter is IYieldAdapter, ERC721Holder, AccessControl, Pausable {
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
     * @notice Unsupported pool
     */
    error UnsupportedPool();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Not KYC approved
     */
    error NotKycApproved();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pool added
     * @param pool Pool address
     */
    event PoolAdded(address indexed pool);

    /**
     * @notice Pool removed
     * @param pool Pool address
     */
    event PoolRemoved(address indexed pool);

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass
     */
    address internal immutable _yieldPass;

    /**
     * @notice XAI Pool factory
     */
    IPoolFactory internal immutable _xaiPoolFactory;

    /**
     * @notice XAI Sentry node license
     */
    INodeLicense internal immutable _xaiSentryNodeLicense;

    /**
     * @notice esXAI token
     */
    IERC20 internal immutable _esXaiToken;

    /**
     * @notice XAI Referee
     */
    IReferee internal immutable _xaiReferee;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Assigned pools (token ID to pool)
     */
    mapping(uint256 => address) internal _assignedPools;

    /**
     * @notice Set of all pools (superset of _allowedPools)
     */
    EnumerableSet.AddressSet private _allPools;

    /**
     * @notice Set of allowed pools
     */
    EnumerableSet.AddressSet private _allowedPools;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice XaiYieldAdapter constructor
     */
    constructor(address yieldPass_, address xaiPoolFactory_) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPass = yieldPass_;
        _xaiPoolFactory = IPoolFactory(xaiPoolFactory_);
        _xaiSentryNodeLicense = INodeLicense(_xaiPoolFactory.nodeLicenseAddress());
        _esXaiToken = IERC20(_xaiPoolFactory.esXaiAddress());
        _xaiReferee = IReferee(_xaiPoolFactory.refereeAddress());
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice XaiYieldAdapter initializer
     */
    function initialize(
        address[] memory pools_
    ) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        for (uint256 i; i < pools_.length; i++) {
            /* Add pool to allowlist */
            _allowedPools.add(pools_[i]);

            /* Add pool to all pools */
            _allPools.add(pools_[i]);
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
        return "XAI Yield Adapter";
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function token() public view returns (address) {
        return address(_esXaiToken);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function cumulativeYield() public view returns (uint256) {
        /* Get pools */
        address[] memory pools = _allPools.values();

        /* Compute accumulative yield */
        uint256 amount;
        for (uint256 i; i < pools.length; i++) {
            amount += IPool(pools[i]).keyBucket().accumulativeDividendOf(address(this));
        }

        return amount;
    }

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPass() public view returns (address) {
        return _yieldPass;
    }

    /**
     * @notice Get XAI pool factory
     * @return Pool factory address
     */
    function xaiPoolFactory() public view returns (address) {
        return address(_xaiPoolFactory);
    }

    /**
     * @notice Get XAI sentry node license
     * @return Sentry node license address
     */
    function xaiSentryNodeLicense() public view returns (address) {
        return address(_xaiSentryNodeLicense);
    }

    /**
     * @notice Get XAI referee
     * @return Referee address
     */
    function xaiReferee() public view returns (address) {
        return address(_xaiReferee);
    }

    /**
     * @notice Get allowed pools
     * @return Allowed pools
     */
    function allowedPools() public view returns (address[] memory) {
        return _allowedPools.values();
    }

    /**
     * @notice Get all pools
     * @return All pools
     */
    function allPools() public view returns (address[] memory) {
        return _allPools.values();
    }

    /*------------------------------------------------------------------------*/
    /* Yield Pass API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function setup(
        uint64,
        address account,
        uint256[] calldata tokenIds,
        bytes calldata setupData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address[] memory) {
        /* Validate KYC'd */
        if (!_xaiReferee.isKycApproved(account)) revert NotKycApproved();

        /* Decode setup data */
        (address[] memory pools, uint256[] memory quantities) = abi.decode(setupData, (address[], uint256[]));

        /* Validate quantities */
        if (quantities.length != pools.length) revert InvalidSetupData();

        uint256 index;
        for (uint256 i; i < pools.length; i++) {
            /* Validate pool is allowed */
            if (!_allowedPools.contains(pools[i])) revert UnsupportedPool();

            /* Get pool token ids */
            uint256[] memory poolTokenIds = tokenIds[index:index + quantities[i]];

            /* Assign pools */
            for (uint256 j; j < poolTokenIds.length; j++) {
                _assignedPools[poolTokenIds[j]] = pools[i];
            }

            /* Transfer licenses */
            _xaiSentryNodeLicense.transferStakedKeys(account, address(this), pools[i], poolTokenIds);

            /* Increment index */
            index += quantities[i];
        }

        /* Validate total quantities */
        if (index != tokenIds.length) revert InvalidSetupData();

        return pools;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(uint64, bytes calldata) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (uint256) {
        /* Snapshot balance before */
        uint256 balanceBefore = _esXaiToken.balanceOf(address(this));

        /* Claim from all pools */
        _xaiPoolFactory.claimFromPools(_allPools.values());

        /* Snapshot balance after */
        uint256 balanceAfter = _esXaiToken.balanceOf(address(this));

        /* Compute yield amount */
        uint256 yieldAmount = balanceAfter - balanceBefore;

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function claim(address recipient, uint256 amount) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Transfer yield amount to recipient */
        if (amount > 0) _esXaiToken.safeTransfer(recipient, amount);
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
     * @dev Pass tokenIds sorted by pool for gas optimization
     */
    function withdraw(
        address recipient,
        uint256[] calldata tokenIds
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Validate token ids */
        if (tokenIds.length == 0) revert InvalidTokenIds();

        uint256 index;
        uint256 lastIndex = tokenIds.length - 1;
        for (uint256 i; i < tokenIds.length; i++) {
            /* Get assigned pool */
            address pool = _assignedPools[tokenIds[i]];

            /* Delete assigned pool mapping */
            delete _assignedPools[tokenIds[i]];

            /* Batch transfer keys by pool */
            if ((i != lastIndex && _assignedPools[tokenIds[i + 1]] != pool) || i == lastIndex) {
                /* Transfer keys to recipient */
                _xaiSentryNodeLicense.transferStakedKeys(address(this), recipient, pool, tokenIds[index:i + 1]);

                /* Reset start index */
                index = i + 1;
            }
        }
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add pool to allowlist
     * @param pools Pools to add
     */
    function addPools(
        address[] memory pools
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < pools.length; i++) {
            /* Add pool to allowed pools */
            _allowedPools.add(pools[i]);

            /* Add pool to all pools */
            _allPools.add(pools[i]);

            emit PoolAdded(pools[i]);
        }
    }

    /**
     * @notice Remove pools from allowlist
     * @param pools Pools to remove
     */
    function removePools(
        address[] memory pools
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < pools.length; i++) {
            /* Remove pool from allowed pools */
            _allowedPools.remove(pools[i]);

            emit PoolRemoved(pools[i]);
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
}
