// SPDX-License-Identifier: MIT
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
     * @return Yield token
     */
    function token() external view returns (address);

    /**
     * @notice Get cumulative yield
     * @return Cumulative yield token amount
     */
    function cumulativeYield() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Yield Adapter API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Setup token IDs for yield
     * @param expiryTime Expiry timestamp
     * @param account Account
     * @param nodeTokenIds Node token IDs
     * @param setupData Setup data
     * @return Operators
     */
    function setup(
        uint64 expiryTime,
        address account,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData
    ) external returns (address[] memory);

    /**
     * @notice Harvest yield
     * @param expiryTime Expiry timestamp
     * @param harvestData Harvest data
     * @return Yield token amount harvested
     */
    function harvest(uint64 expiryTime, bytes calldata harvestData) external returns (uint256);

    /**
     * @notice Claim yield
     * @param recipient Recipient
     * @param amount Yield token amount
     */
    function claim(address recipient, uint256 amount) external;

    /**
     * @notice Initiate withdraw of token IDs
     * @param expiryTime Expiry timestamp
     * @param nodeTokenIds Node token IDs
     */
    function initiateWithdraw(uint64 expiryTime, uint256[] calldata nodeTokenIds) external;

    /**
     * @notice Withdraw token IDs
     * @param recipient Recipient
     * @param nodeTokenIds Node token IDs
     */
    function withdraw(address recipient, uint256[] calldata nodeTokenIds) external;
}
