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
    /* Error */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid token owner
     */
    error InvalidOwner();

    /**
     * @notice Invalid length
     */
    error InvalidLength();

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
    /* Access Control Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass role
     */
    bytes32 public constant YIELD_PASS_ROLE = keccak256("YIELD_PASS_ROLE");

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
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass
     */
    address internal immutable _yieldPass;

    /**
     * @notice Pool factory
     */
    IPoolFactory internal immutable _poolFactory;

    /**
     * @notice esXAI token
     */
    IERC20 internal immutable _esXaiToken;

    /**
     * @notice Referee
     */
    IReferee internal immutable _referee;

    /**
     * @notice Sentry node license
     */
    IERC721 internal immutable _sentryNodeLicense;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialized
     */
    bool internal _initialized;

    /**
     * @notice Set of allowed pools
     */
    EnumerableSet.AddressSet private _allowedPools;

    /**
     * @notice Mapping of tokenId to pool
     */
    mapping(uint256 => address) internal _pools;

    /**
     * @notice Mapping of token ID to unstake request index
     */
    mapping(uint256 => uint256) internal _unstakeRequestIndexes;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldAdapter constructor
     */
    constructor(address yieldPass_, address xaiPoolFactory_) {
        /* Disable initialization of implementation contract */
        _initialized = true;

        _yieldPass = yieldPass_;
        _poolFactory = IPoolFactory(xaiPoolFactory_);
        _esXaiToken = IERC20(_poolFactory.esXaiAddress());
        _referee = IReferee(_poolFactory.refereeAddress());
        _sentryNodeLicense = IERC721(_poolFactory.nodeLicenseAddress());
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldAdapter initializer
     */
    function initialize(
        address[] memory pools_
    ) external {
        require(!_initialized, "Already initialized");

        _initialized = true;

        for (uint256 i = 0; i < pools_.length; i++) {
            /* Add pool to allowlist */
            _allowedPools.add(pools_[i]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_PASS_ROLE, _yieldPass);
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
        address[] memory pools = _allowedPools.values();

        /* Compute accumulative yield */
        uint256 amount;
        for (uint256 i = 0; i < pools.length; i++) {
            amount += IPool(pools[i]).keyBucket().accumulativeDividendOf(address(this));
        }
        return amount;
    }

    /**
     * @notice Get pool factory
     * @return Pool factory address
     */
    function poolFactory() public view returns (address) {
        return address(_poolFactory);
    }

    /**
     * @notice Get sentry node license
     * @return Sentry node license address
     */
    function license() public view returns (address) {
        return address(_sentryNodeLicense);
    }

    /**
     * @notice Get referee
     * @return Referee address
     */
    function referee() public view returns (address) {
        return address(_referee);
    }

    /**
     * @notice Get allowed pools
     * @return Allowed pools
     */
    function allowedPools() public view returns (address[] memory) {
        return _allowedPools.values();
    }

    /*------------------------------------------------------------------------*/
    /* Yield Pass API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IYieldAdapter
     */
    function setup(
        uint256[] calldata tokenIds,
        uint64,
        address minter,
        address discountPassRecipient,
        bytes calldata setupData
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (address[] memory) {
        /* Validate KYC'd */
        if (!_referee.isKycApproved(minter) || !_referee.isKycApproved(discountPassRecipient)) revert NotKycApproved();

        /* Decode setup data */
        (address[] memory pools, uint256[] memory quantities) = abi.decode(setupData, (address[], uint256[]));

        /* Validate length */
        if (pools.length != quantities.length) revert InvalidLength();

        /* Pools */
        uint256 count;
        for (uint256 i; i < pools.length; i++) {
            /* Validate pool is allowed */
            if (!_allowedPools.contains(pools[i])) revert UnsupportedPool();

            /* Keys */
            uint256[] memory keys = new uint256[](quantities[i]);

            /* Validate keys ownership and update token ID to pools mapping */
            for (uint256 j; j < quantities[i]; j++) {
                /* Validate this contract owns the keys */
                if (_sentryNodeLicense.ownerOf(tokenIds[count]) != address(this)) revert InvalidOwner();

                /* Store pool */
                _pools[tokenIds[count]] = pools[i];

                /* Store key */
                keys[j] = tokenIds[count++];
            }

            /* Stake key */
            _poolFactory.stakeKeys(pools[i], keys);
        }

        /* Validate all keys are staked */
        if (count != tokenIds.length) revert InvalidLength();

        return pools;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function validateClaim(
        address
    ) external view whenNotPaused returns (bool) {
        return true;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function harvest(uint64, bytes calldata) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (uint256) {
        /* Snapshot balance before */
        uint256 balanceBefore = _esXaiToken.balanceOf(address(this));

        /* Claim from pools */
        _poolFactory.claimFromPools(_allowedPools.values());

        /* Snapshot balance after */
        uint256 balanceAfter = _esXaiToken.balanceOf(address(this));

        /* Compute yield amount */
        uint256 yieldAmount = balanceAfter - balanceBefore;

        /* Transfer yield amount to yield pass contract */
        if (yieldAmount > 0) _esXaiToken.safeTransfer(_yieldPass, yieldAmount);

        return yieldAmount;
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function initiateTeardown(
        uint256[] calldata tokenIds,
        uint64 expiry
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused returns (bytes memory) {
        /* Validate prepare teardown is within window */
        if (block.timestamp <= expiry - _poolFactory.unstakeKeysDelayPeriod()) revert InvalidWindow();

        /* Create unstake requests */
        uint256[] memory unstakeRequestIndexes = new uint256[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            /* Get pool */
            address pool = _pools[tokenIds[i]];

            /* Create unstake request */
            _poolFactory.createUnstakeKeyRequest(pool, 1);

            /* Unstake request ID */
            uint256 unstakeRequestIndex = IPool(pool).getUnstakeRequestCount(address(this)) - 1;

            /* Store unstake request index */
            _unstakeRequestIndexes[tokenIds[i]] = unstakeRequestIndex;

            /* Store unstake request index */
            unstakeRequestIndexes[i] = unstakeRequestIndex;
        }

        /* Return unstake request indexes */
        return abi.encode(unstakeRequestIndexes);
    }

    /**
     * @inheritdoc IYieldAdapter
     */
    function teardown(
        uint256[] calldata tokenIds,
        address recipient,
        bytes calldata
    ) external onlyRole(YIELD_PASS_ROLE) whenNotPaused {
        for (uint256 i; i < tokenIds.length; i++) {
            /* Get pool */
            address pool = _pools[tokenIds[i]];

            /* Get unstake request index */
            uint256 unstakeRequestIndex = _unstakeRequestIndexes[tokenIds[i]];

            /* Remove token ID to unstake request index mapping */
            delete _unstakeRequestIndexes[tokenIds[i]];

            /* Remove token ID to pool from mapping */
            delete _pools[tokenIds[i]];

            /* Unstake from pool */
            uint256[] memory licenses = new uint256[](1);
            licenses[0] = tokenIds[i];
            _poolFactory.unstakeKeys(pool, unstakeRequestIndex, licenses);

            /* Transfer key to recipient */
            _sentryNodeLicense.transferFrom(address(this), recipient, tokenIds[i]);
        }
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add or remove pool from whitelist
     * @param pool Pool to add or remove
     */
    function updatePools(
        address pool
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Validate pool is allowed */
        if (_allowedPools.contains(pool)) {
            _allowedPools.remove(pool);

            emit PoolRemoved(pool);
        } else {
            _allowedPools.add(pool);

            emit PoolAdded(pool);
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
