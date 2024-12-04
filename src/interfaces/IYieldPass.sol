//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IYieldPass is IERC721Receiver {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass state
     * @param startTime Start time
     * @param expiry Expiry
     * @param token Token
     * @param yieldPass Yield pass
     * @param discountPass Discount pass
     */
    struct YieldPassInfo {
        uint64 startTime;
        uint64 expiry;
        address token;
        address yieldPass;
        address discountPass;
    }

    /**
     * @notice Yield claim state
     * @param balance Yield balance
     * @param shares Total claim shares
     * @param total Total yield accrued
     */
    struct YieldClaimState {
        uint256 balance;
        uint256 shares;
        uint256 total;
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid yield pass
     */
    error InvalidYieldPass();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid adapter
     */
    error InvalidAdapter();

    /**
     * @notice Invalid signature
     */
    error InvalidSignature();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Invalid claim
     */
    error InvalidClaim();

    /**
     * @notice Invalid redemption
     */
    error InvalidRedemption();

    /**
     * @notice Invalid NFT withdrawal
     */
    error InvalidWithdrawal();

    /**
     * @notice Invalid expiry
     */
    error InvalidExpiry();

    /**
     * @notice Yield pass already deployed
     */
    error AlreadyDeployed();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when Yield passs and a discount pass are minted
     * @param account Account
     * @param yieldPass Yield pass
     * @param token NFT token
     * @param yieldPassAmount Yield pass amount
     * @param discountPass Discount pass
     * @param tokenIds NFT token (and discount pass) IDs
     * @param operators Operators
     */
    event Minted(
        address indexed account,
        address indexed yieldPass,
        address indexed token,
        uint256 yieldPassAmount,
        address discountPass,
        uint256[] tokenIds,
        address[] operators
    );

    /**
     * @notice Emitted when yield is retrieved from yield adapter
     * @param yieldPass Yield pass
     * @param amount Amount retrieved
     */
    event Harvested(address indexed yieldPass, uint256 amount);

    /**
     * @notice Emitted when yield is claimed
     * @param account Account
     * @param yieldPass Yield pass
     * @param recipient Recipient
     * @param yieldPassAmount Yield pass amount
     * @param yieldToken Yield token
     * @param yieldAmount Yield amount
     */
    event Claimed(
        address indexed account,
        address indexed yieldPass,
        address indexed recipient,
        uint256 yieldPassAmount,
        address yieldToken,
        uint256 yieldAmount
    );

    /**
     * @notice Emitted when discount pass is used for redemption
     * @param account Account
     * @param yieldPass Yield pass
     * @param token Token
     * @param discountPass Discount pass
     * @param tokenIds Token (and discount pass) IDs
     * @param teardownData Teardown data
     */
    event Redeemed(
        address indexed account,
        address indexed yieldPass,
        address indexed token,
        address discountPass,
        uint256[] tokenIds,
        bytes teardownData
    );

    /**
     * @notice Emitted when Yield passs are burned
     * @param account Account
     * @param yieldPass Yield pass
     * @param token Token
     * @param recipient Recipient
     * @param discountPass Discount pass
     * @param tokenIds Token (and discount pass) IDs
     */
    event Withdrawn(
        address indexed account,
        address indexed yieldPass,
        address indexed token,
        address recipient,
        address discountPass,
        uint256[] tokenIds
    );

    /**
     * @notice Emitted when yield adapter is updated
     * @param yieldPass Yield pass
     * @param yieldAdapter Yield adapter
     */
    event AdapterUpdated(address indexed yieldPass, address indexed yieldAdapter);

    /**
     * @notice Emitted when yield pass is deployed
     * @param token NFT Token address
     * @param expiry Expiry timestamp
     * @param yieldPass Yield pass
     * @param discountPass Discount pass
     * @param adapter Yield adapter
     */
    event YieldPassDeployed(
        address indexed token, uint256 indexed expiry, address indexed yieldPass, address discountPass, address adapter
    );

    /**
     * @notice Emitted when nonce is increased
     * @param account Account
     * @param nonce Nonce
     */
    event NonceIncreased(address indexed account, uint256 nonce);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get yield pass info
     * @param yieldPass Yield pass
     * @return Yield pass info
     */
    function yieldPassInfo(
        address yieldPass
    ) external view returns (YieldPassInfo memory);

    /**
     * @notice Get yield pass infos
     * @param offset Offset
     * @param count Count
     * @return Yield pass infos
     */
    function yieldPassInfos(uint256 offset, uint256 count) external view returns (YieldPassInfo[] memory);

    /**
     * @notice Get yield claim state
     * @param yieldPass Yield pass
     * @return YieldClaimState
     */
    function claimState(
        address yieldPass
    ) external view returns (YieldClaimState memory);

    /**
     * @notice Get yield adapter
     * @param yieldPass Yield pass
     * @return Yield adapter
     */
    function yieldAdapter(
        address yieldPass
    ) external view returns (address);

    /**
     * @notice Get nonce
     * @param account Account
     * @return Nonce
     */
    function nonce(
        address account
    ) external view returns (uint256);

    /**
     * @notice Get total cumulative yield
     * @param yieldPass Yield pass
     * @return Cumulative yield
     */
    function cumulativeYield(
        address yieldPass
    ) external view returns (uint256);

    /**
     * @notice Get cumulative yield given yield pass amount
     * @param yieldPass Yield pass
     * @param yieldPassAmount Yield pass token amount
     * @return Cumulative yield
     */
    function cumulativeYield(address yieldPass, uint256 yieldPassAmount) external view returns (uint256);

    /**
     * @notice Get claimable amount for yield
     * @param yieldPass Yield pass
     * @param yieldPassAmount Yield pass token amount
     * @return Claimable yield
     */
    function claimable(address yieldPass, uint256 yieldPassAmount) external view returns (uint256);

    /**
     * @notice Get yield pass token amount for mint
     * @param yieldPass Yield pass
     * @param count Count
     * @return Yield pass token amount
     */
    function quoteMint(address yieldPass, uint256 count) external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* User APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper to mint a yield pass and a discount pass for an NFT token IDs
     * @param yieldPass Yield pass
     * @param account Account
     * @param tokenIds NFT Token IDs
     * @param yieldPassRecipient Yield pass recipient
     * @param discountPassRecipient Discount pass recipient
     * @param setupData Setup data
     * @param transferSignature Transfer signature
     * @return Yield pass amount
     */
    function mint(
        address yieldPass,
        address account,
        uint256[] calldata tokenIds,
        address yieldPassRecipient,
        address discountPassRecipient,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) external returns (uint256);

    /**
     * @notice Harvest yield from yield adapter
     * @param yieldPass Yield pass
     * @param harvestData Harvest data
     * @return Amount harvested
     */
    function harvest(address yieldPass, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Claim yield
     * @param yieldPass Yield pass
     * @param recipient Recipient
     * @param amount Yield pass amount
     * @return Yield amount
     */
    function claim(address yieldPass, address recipient, uint256 amount) external returns (uint256);

    /**
     * @notice Redeem yield pass
     * @param yieldPass Yield pass
     * @param tokenIds NFT token IDs
     * @return Teardown data
     */
    function redeem(address yieldPass, uint256[] calldata tokenIds) external returns (bytes memory);

    /**
     * @notice Withdrawal NFT
     * @param yieldPass Yield pass
     * @param recipient Recipient
     * @param tokenIds NFT token IDs
     * @param harvestData Harvest data
     * @param teardownData Teardown data
     */
    function withdraw(
        address yieldPass,
        address recipient,
        uint256[] calldata tokenIds,
        bytes calldata harvestData,
        bytes calldata teardownData
    ) external;

    /**
     * @notice Helper to increase nonce
     */
    function increaseNonce() external;

    /*------------------------------------------------------------------------*/
    /* Admin APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deploy Yield pass
     * @param token NFT Token address
     * @param startTime Start time
     * @param expiry Expiry timestamp
     * @param isTransferable True if token is transferable
     * @param adapter Yield adapter
     * @return Yield pass address, discount pass address
     */
    function deployYieldPass(
        address token,
        uint64 startTime,
        uint64 expiry,
        bool isTransferable,
        address adapter
    ) external returns (address, address);

    /**
     * @notice Set yield adapter for Yield pass
     * @param yieldPass Yield pass
     * @param adapter Yield adapter
     */
    function setYieldAdapter(address yieldPass, address adapter) external;

    /**
     * @notice Set user locked for discount pass token
     * @param yieldPass Yield pass
     * @param isUserLocked True if user locked enabled
     */
    function setUserLocked(address yieldPass, bool isUserLocked) external;
}
