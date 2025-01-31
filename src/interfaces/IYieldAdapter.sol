// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Yield Adapter Interface
 * @author MetaStreet Foundation
 */
interface IYieldAdapter is IERC721Receiver {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid recipient
     */
    error InvalidRecipient();

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
     * @param account Account
     * @param nodeTokenIds Node token IDs
     * @param setupData Setup data
     * @return Operators
     */
    function setup(
        address account,
        uint256[] calldata nodeTokenIds,
        bytes calldata setupData
    ) external returns (address[] memory);

    /**
     * @notice Harvest yield
     * @param harvestData Harvest data
     * @return Yield token amount harvested
     */
    function harvest(
        bytes calldata harvestData
    ) external returns (uint256);

    /**
     * @notice Claim yield
     * @param recipient Recipient
     * @param amount Yield token amount
     */
    function claim(address recipient, uint256 amount) external;

    /**
     * @notice Redeem token IDs
     * @param recipient Recipient
     * @param nodeTokenIds Node token IDs
     * @param redemptionHash Redemption hash
     */
    function redeem(address recipient, uint256[] calldata nodeTokenIds, bytes32 redemptionHash) external;

    /**
     * @notice Withdraw token IDs
     * @param nodeTokenIds Node token IDs
     * @param redemptionHash Redemption hash
     * @return Recipient
     */
    function withdraw(uint256[] calldata nodeTokenIds, bytes32 redemptionHash) external returns (address);
}
