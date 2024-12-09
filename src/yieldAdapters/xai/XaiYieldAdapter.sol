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
    function stakeKeys(address pool, uint256[] memory keyIds) external;
    function unstakeKeys(address pool, uint256 unstakeRequestIndex, uint256[] memory keyIds) external;
    function claimFromPools(
        address[] memory pools
    ) external;
    function createUnstakeKeyRequest(address pool, uint256 keyAmount) external;
    function unstakeKeysDelayPeriod() external view returns (uint256);
}

/**
 * @title XAI Pool Interface
 */
interface IPool {
    function getUnstakeRequestCount(
        address account
    ) external view returns (uint256);
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

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

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
    IERC721 internal immutable _xaiSentryNodeLicense;

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
     * @notice Set of all pools (superset of _allowedPools)
     */
    EnumerableSet.AddressSet private _allPools;

    /**
     * @notice Set of allowed pools
     */
    EnumerableSet.AddressSet private _allowedPools;

    /**
     * @notice Mapping of token ID to assigned pool
     */
    mapping(uint256 => address) internal _assignedPools;

    /**
     * @notice Mapping of token ID to unstake request index
     */
    mapping(uint256 => uint256) internal _unstakeRequestIndexes;

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
        _xaiSentryNodeLicense = IERC721(_xaiPoolFactory.nodeLicenseAddress());
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

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_PASS_ROLE, _yieldPass);
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
        address pool = abi.decode(setupData, (address));

        /* Validate pool is allowed */
        if (!_allowedPools.contains(pool)) revert UnsupportedPool();

        for (uint256 i; i < tokenIds.length; i++) {
            /* Transfer license NFT from account to yield adapter */
            IERC721(_xaiSentryNodeLicense).safeTransferFrom(account, address(this), tokenIds[i]);

            /* Store pool */
            _assignedPools[tokenIds[i]] = pool;
        }

        /* Stake licenses */
        _xaiPoolFactory.stakeKeys(pool, tokenIds);

        /* Return operators (pool) */
        address[] memory operators = new address[](1);
        operators[0] = pool;

        return operators;
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
        uint256[] calldata tokenIds
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        /* Validate unstaking would complete after expiry */
        if (block.timestamp <= expiryTime - _xaiPoolFactory.unstakeKeysDelayPeriod()) revert InvalidWindow();

        /* Create unstake requests */
        for (uint256 i; i < tokenIds.length; i++) {
            /* Get assigned pool */
            address pool = _assignedPools[tokenIds[i]];

            /* Create unstake request */
            _xaiPoolFactory.createUnstakeKeyRequest(pool, 1);

            /* Unstake request ID */
            uint256 unstakeRequestIndex = IPool(pool).getUnstakeRequestCount(address(this)) - 1;

            /* Store unstake request index */
            _unstakeRequestIndexes[tokenIds[i]] = unstakeRequestIndex;
        }
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function withdraw(
        address recipient,
        uint256[] calldata tokenIds
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        for (uint256 i; i < tokenIds.length; i++) {
            /* Get assigned pool */
            address pool = _assignedPools[tokenIds[i]];

            /* Get unstake request index */
            uint256 unstakeRequestIndex = _unstakeRequestIndexes[tokenIds[i]];

            /* Delete unstake request index mapping */
            delete _unstakeRequestIndexes[tokenIds[i]];

            /* Delete assigned pool mapping */
            delete _assignedPools[tokenIds[i]];

            /* Unstake from pool */
            uint256[] memory licenses = new uint256[](1);
            licenses[0] = tokenIds[i];
            _xaiPoolFactory.unstakeKeys(pool, unstakeRequestIndex, licenses);

            /* Transfer license NFT to recipient */
            _xaiSentryNodeLicense.transferFrom(address(this), recipient, tokenIds[i]);
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
