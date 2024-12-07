//SPDX-License-Identifier: MIT
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
     * @notice Yield pass state
     * @param startTime Start timestamp
     * @param expiry Expiry timestamp
     * @param token NFT token
     * @param yieldPass Yield pass token
     * @param discountPass Discount pass token
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
     * @param balance Yield balance (in yield tokens)
     * @param shares Total claim shares (in yield pass tokens)
     * @param total Total yield accrued (in yield tokens)
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
     * @notice Emitted when yield pass and discount pass are minted
     * @param account Account
     * @param yieldPass Yield pass token
     * @param token NFT token
     * @param yieldPassAmount Yield pass amount
     * @param discountPass Discount pass token
     * @param tokenIds NFT (and discount pass) token IDs
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
     * @notice Emitted when yield is harvest from yield adapter
     * @param yieldPass Yield pass token
     * @param amount Yield token amount harvested
     */
    event Harvested(address indexed yieldPass, uint256 amount);

    /**
     * @notice Emitted when yield is claimed
     * @param account Account
     * @param yieldPass Yield pass token
     * @param recipient Recipient
     * @param yieldPassAmount Yield pass amount
     * @param yieldToken Yield token
     * @param yieldAmount Yield token amount
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
     * @notice Emitted when discount pass is redeemed
     * @param account Account
     * @param yieldPass Yield pass token
     * @param token NFT token
     * @param discountPass Discount pass token
     * @param tokenIds NFT (and discount pass) token IDs
     */
    event Redeemed(
        address indexed account,
        address indexed yieldPass,
        address indexed token,
        address discountPass,
        uint256[] tokenIds
    );

    /**
     * @notice Emitted when NFTs are withdrawn
     * @param account Account
     * @param yieldPass Yield pass token
     * @param token NFT token
     * @param recipient Recipient
     * @param discountPass Discount pass token
     * @param tokenIds NFT (and discount pass) token IDs
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
     * @notice Emitted when yield pass and discount pass tokens are deployed
     * @param token NFT token
     * @param expiry Expiry timestamp
     * @param yieldPass Yield pass token
     * @param startTime Start timestamp
     * @param discountPass Discount pass token
     * @param yieldAdapter Yield adapter
     */
    event YieldPassDeployed(
        address indexed token,
        uint256 indexed expiry,
        address indexed yieldPass,
        uint256 startTime,
        address discountPass,
        address yieldAdapter
    );

    /**
     * @notice Emitted when account nonce is increased
     * @param account Account
     * @param nonce Nonce
     */
    event NonceIncreased(address indexed account, uint256 nonce);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get yield pass name
     * @return Yield pass name
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
     * @notice Get yield adapter
     * @param yieldPass Yield pass token
     * @return Yield adapter
     */
    function yieldAdapter(
        address yieldPass
    ) external view returns (address);

    /**
     * @notice Get account nonce
     * @param account Account
     * @return Nonce
     */
    function nonce(
        address account
    ) external view returns (uint256);

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
     * @notice Get claimable amount for yield pass amount
     * @param yieldPass Yield pass token
     * @param yieldPassAmount Yield pass amount
     * @return Claimable yield in yield tokens
     */
    function claimable(address yieldPass, uint256 yieldPassAmount) external view returns (uint256);

    /**
     * @notice Get yield pass token amount for mint
     * @param yieldPass Yield pass token
     * @param count NFT count
     * @return Yield pass amount
     */
    function quoteMint(address yieldPass, uint256 count) external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* User APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint a yield pass and a discount pass for NFT token IDs
     * @param yieldPass Yield pass token
     * @param account Account holding NFT
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
     * @param yieldPass Yield pass token
     * @param harvestData Harvest data
     * @return Yield token amount harvested
     */
    function harvest(address yieldPass, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Claim yield
     * @param yieldPass Yield pass token
     * @param recipient Recipient
     * @param amount Yield pass amount
     * @return Yield token amount
     */
    function claim(address yieldPass, address recipient, uint256 amount) external returns (uint256);

    /**
     * @notice Redeem discount pass
     * @param yieldPass Yield pass token
     * @param tokenIds NFT (and discount pass) token IDs
     */
    function redeem(address yieldPass, uint256[] calldata tokenIds) external;

    /**
     * @notice Withdraw NFTs
     * @param yieldPass Yield pass token
     * @param recipient Recipient
     * @param tokenIds NFT token IDs
     */
    function withdraw(address yieldPass, address recipient, uint256[] calldata tokenIds) external;

    /**
     * @notice Increase account nonce
     */
    function increaseNonce() external;

    /*------------------------------------------------------------------------*/
    /* Admin APIs */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deploy Yield Pass for an NFT
     * @param token NFT token
     * @param startTime Start timestamp
     * @param expiry Expiry timestamp
     * @param isUserLocked True if token is user locked
     * @param adapter Yield adapter
     * @return Yield pass address, discount pass address
     */
    function deployYieldPass(
        address token,
        uint64 startTime,
        uint64 expiry,
        bool isUserLocked,
        address adapter
    ) external returns (address, address);

    /**
     * @notice Set user locked for discount pass token
     * @param yieldPass Yield pass token
     * @param isUserLocked True if user locked enabled
     */
    function setUserLocked(address yieldPass, bool isUserLocked) external;
}
