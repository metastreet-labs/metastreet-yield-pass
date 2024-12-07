//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Yield Adapter Interface
 * @author MetaStreet Foundation
 */
interface IYieldAdapter is IERC721Receiver {
    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

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
     * @notice Get cumulative yield
     * @return Yield amount
     */
    function cumulativeYield() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Yield Adapter API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Setup yield adapter
     * @param tokenIds Token IDs
     * @param expiry Expiry
     * @param account Account
     * @param setupData Setup data
     * @return Operators
     */
    function setup(
        uint256[] calldata tokenIds,
        uint64 expiry,
        address account,
        bytes calldata setupData
    ) external returns (address[] memory);

    /**
     * @notice Harvest yield
     * @param expiry Expiry
     * @param harvestData Harvest data
     * @return Yield amount
     */
    function harvest(uint64 expiry, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Initiate teardown
     * @param tokenIds Token IDs
     * @param expiry Expiry
     * @return Teardown data
     */
    function initiateTeardown(uint256[] calldata tokenIds, uint64 expiry) external returns (bytes memory);

    /**
     * @notice Withdraw yield
     * @param tokenIds Token IDs
     * @param recipient Recipient
     */
    function teardown(uint256[] calldata tokenIds, address recipient) external;

    /**
     * @notice Claim yield
     * @param recipient Recipient
     * @param amount Amount
     * @return Yield token
     */
    function claim(address recipient, uint256 amount) external returns (address);
}
