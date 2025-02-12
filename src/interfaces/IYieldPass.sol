// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Yield Pass Interface
 * @author MetaStreet Foundation
 */
interface IYieldPass is IERC721Receiver {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass info
     * @param startTime Start timestamp
     * @param expiryTime Expiry timestamp
     * @param nodeToken Node token
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param yieldAdapter Yield adapter
     */
    struct YieldPassInfo {
        uint64 startTime;
        uint64 expiryTime;
        address nodeToken;
        address yieldPass;
        address nodePass;
        address yieldAdapter;
    }

    /**
     * @notice Yield claim state
     * @param balance Yield balance in yield tokens
     * @param shares Total claim shares in yield pass tokens
     * @param total Total yield accrued in yield tokens
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
     * @notice Invalid deadline
     */
    error InvalidDeadline();

    /**
     * @notice Invalid signature
     */
    error InvalidSignature();

    /**
     * @notice Invalid window
     */
    error InvalidWindow();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Invalid node redemption
     */
    error InvalidRedemption();

    /**
     * @notice Invalid node withdrawal
     */
    error InvalidWithdrawal();

    /**
     * @notice Invalid expiry
     */
    error InvalidExpiry();

    /**
     * @notice Invalid adapter
     */
    error InvalidAdapter();

    /**
     * @notice Invalid recipient
     */
    error InvalidRecipient();

    /**
     * @notice Invalid token IDs
     */
    error InvalidTokenIds();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when yield pass and node pass are minted
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param account Account holding nodes
     * @param yieldPassRecipient Yield pass recipient
     * @param yieldPassAmount Yield pass amount
     * @param nodePassRecipient Node pass recipient
     * @param nodeToken Node token
     * @param nodeTokenIds Node (and node pass) token IDs
     * @param operators Operators
     */
    event Minted(
        address indexed yieldPass,
        address nodePass,
        address account,
        address indexed yieldPassRecipient,
        uint256 yieldPassAmount,
        address nodePassRecipient,
        address indexed nodeToken,
        uint256[] nodeTokenIds,
        address[] operators
    );

    /**
     * @notice Emitted when yield pass and node pass are minted (deprecated)
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param yieldPassRecipient Yield pass recipient
     * @param yieldPassAmount Yield pass amount
     * @param nodePassRecipient Node pass recipient
     * @param nodeToken Node token
     * @param nodeTokenIds Node (and node pass) token IDs
     * @param operators Operators
     */
    event Minted(
        address indexed yieldPass,
        address nodePass,
        address indexed yieldPassRecipient,
        uint256 yieldPassAmount,
        address nodePassRecipient,
        address indexed nodeToken,
        uint256[] nodeTokenIds,
        address[] operators
    );

    /**
     * @notice Emitted when yield is harvested
     * @param yieldPass Yield pass token
     * @param yieldAmount Yield token amount harvested
     */
    event Harvested(address indexed yieldPass, uint256 yieldAmount);

    /**
     * @notice Emitted when yield is claimed
     * @param yieldPass Yield pass token
     * @param account Account
     * @param yieldPassAmount Yield pass amount
     * @param recipient Recipient
     * @param yieldToken Yield token
     * @param yieldAmount Yield token amount
     */
    event Claimed(
        address indexed yieldPass,
        address indexed account,
        uint256 yieldPassAmount,
        address indexed recipient,
        address yieldToken,
        uint256 yieldAmount
    );

    /**
     * @notice Emitted when node pass is redeemed
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param account Account
     * @param recipient Recipient
     * @param nodeToken Node token
     * @param nodeTokenIds Node (and node pass) token IDs
     */
    event Redeemed(
        address indexed yieldPass,
        address nodePass,
        address indexed account,
        address recipient,
        address indexed nodeToken,
        uint256[] nodeTokenIds
    );

    /**
     * @notice Emitted when nodes are withdrawn
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param account Account
     * @param recipient Recipient
     * @param nodeToken Node token
     * @param nodeTokenIds Node (and node pass) token IDs
     */
    event Withdrawn(
        address indexed yieldPass,
        address nodePass,
        address indexed account,
        address recipient,
        address indexed nodeToken,
        uint256[] nodeTokenIds
    );

    /**
     * @notice Emitted when yield pass and node pass tokens are deployed
     * @param yieldPass Yield pass token
     * @param nodePass Node pass token
     * @param nodeToken Node token
     * @param startTime Start timestamp
     * @param expiryTime Expiry timestamp
     * @param yieldAdapter Yield adapter
     */
    event YieldPassDeployed(
        address indexed yieldPass,
        address nodePass,
        address indexed nodeToken,
        uint256 startTime,
        uint256 indexed expiryTime,
        address yieldAdapter
    );

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get yield pass factory name
     * @return Yield pass factory name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get yield pass info
     * @param yieldPass Yield pass token
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
     * @param yieldPass Yield pass token
     * @return Yield claim state
     */
    function claimState(
        address yieldPass
    ) external view returns (YieldClaimState memory);

    /**
     * @notice Get total cumulative yield
     * @param yieldPass Yield pass token
     * @return Cumulative yield in yield tokens
     */
    function cumulativeYield(
        address yieldPass
    ) external view returns (uint256);

    /**
     * @notice Get cumulative yield for yield pass amount
     * @param yieldPass Yield pass token
     * @param yieldPassAmount Yield pass amount
     * @return Cumulative yield in yield tokens
     */
    function cumulativeYield(address yieldPass, uint256 yieldPassAmount) external view returns (uint256);

    /**
     * @notice Get total claimable yield
     * @param yieldPass Yield pass token
     * @return Claimable yield in yield tokens
     */
    function claimableYield(
        address yieldPass
    ) external view returns (uint256);

    /**
     * @notice Get claimable yield for yield pass amount
     * @param yieldPass Yield pass token
     * @param yieldPassAmount Yield pass amount
     * @return Claimable yield in yield tokens
     */
    function claimableYield(address yieldPass, uint256 yieldPassAmount) external view returns (uint256);

    /**
     * @notice Get yield pass token amount for mint
     * @param yieldPass Yield pass token
     * @param count Node count
     * @return Yield pass amount
     */
    function quoteMint(address yieldPass, uint256 count) external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* User APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint yield pass and node pass for node token IDs
     * @param yieldPass Yield pass token
     * @param yieldPassRecipient Yield pass recipient
     * @param nodePassRecipient Node pass recipient
     * @param deadline Deadline
     * @param nodeTokenIds Node token IDs
     * @param setupData Setup data
     * @return Yield pass amount
     */
    function mint(
        address yieldPass,
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData
    ) external returns (uint256);

    /**
     * @notice Mint yield pass and node pass for node token IDs (smart account friendly version)
     * @param yieldPass Yield pass token
     * @param account Account holding nodes
     * @param yieldPassRecipient Yield pass recipient
     * @param nodePassRecipient Node pass recipient
     * @param deadline Deadline
     * @param nodeTokenIds Node token IDs
     * @param setupData Setup data
     * @param transferSignature Transfer signature
     * @return Yield pass amount
     */
    function mint(
        address yieldPass,
        address account,
        address yieldPassRecipient,
        address nodePassRecipient,
        uint256 deadline,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData,
        bytes calldata transferSignature
    ) external returns (uint256);

    /**
     * @notice Harvest yield
     * @param yieldPass Yield pass token
     * @param harvestData Harvest data
     * @return Yield token amount harvested
     */
    function harvest(address yieldPass, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Claim yield
     * @param yieldPass Yield pass token
     * @param recipient Recipient
     * @param yieldPassAmount Yield pass amount
     * @return Yield token amount
     */
    function claim(address yieldPass, address recipient, uint256 yieldPassAmount) external returns (uint256);

    /**
     * @notice Redeem node passes
     * @param yieldPass Yield pass token
     * @param recipient Recipient
     * @param nodeTokenIds Node (and node pass) token IDs
     */
    function redeem(address yieldPass, address recipient, uint256[] calldata nodeTokenIds) external;

    /**
     * @notice Withdraw nodes
     * @param yieldPass Yield pass token
     * @param nodeTokenIds Node token IDs
     */
    function withdraw(address yieldPass, uint256[] calldata nodeTokenIds) external;

    /*------------------------------------------------------------------------*/
    /* Admin APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deploy Yield Pass and Node Pass tokens for a node token
     * @param nodeToken Node token
     * @param startTime Start timestamp
     * @param expiryTime Expiry timestamp
     * @param adapter Yield adapter
     * @return Yield pass address, node pass address
     */
    function deployYieldPass(
        address nodeToken,
        uint64 startTime,
        uint64 expiryTime,
        address adapter
    ) external returns (address, address);
}
