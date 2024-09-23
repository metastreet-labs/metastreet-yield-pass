//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IYieldAdapter is IERC721Receiver {
    /**
     * @notice Get yield adapter name
     * @return Name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get yield token
     * @return Token address
     */
    function token() external view returns (address);

    /**
     * @notice Get token delegatee
     * @return Delegatee
     */
    function tokenDelegatee(uint256 tokenId) external view returns (address);

    /**
     * @notice Get cumulative yield
     * @return Yield amount
     */
    function cumulativeYield() external view returns (uint256);

    /**
     * @notice Setup yield adapter
     * @param tokenId Token ID
     * @param expiry Expiry
     * @param minter Minter
     * @param discountPassRecipient Discount pass recipient
     * @param setupData Setup data
     */
    function setup(
        uint256 tokenId,
        uint64 expiry,
        address minter,
        address discountPassRecipient,
        bytes calldata setupData
    ) external;

    /**
     * @notice Harvest yield
     * @param expiry Expiry
     * @param harvestData Harvest data
     * @return Yield amount
     */
    function harvest(uint64 expiry, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Validate claim
     * @param claimant Claimant
     * @return True if valid, false otherwise
     */
    function validateClaim(address claimant) external returns (bool);

    /**
     * @notice Initiate teardown
     * @param tokenId Token ID
     * @param expiry Expiry
     * @return Teardown data
     */
    function initiateTeardown(uint256 tokenId, uint64 expiry) external returns (bytes memory);

    /**
     * @notice Withdraw yield
     * @param tokenId Token ID
     * @param receiver Receiver
     * @param teardownData Teardown data
     */
    function teardown(uint256 tokenId, address receiver, bytes calldata teardownData) external;
}
