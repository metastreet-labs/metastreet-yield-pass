// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Yield Pass Token (ERC20)
 * @author MetaStreet Foundation
 */
contract YieldPassToken is ERC20 {
    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Yield pass factory
     */
    address internal immutable _yieldPassFactory;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice YieldPassToken constructor
     * @param name_ Name
     * @param symbol_ Symbol
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _yieldPassFactory = msg.sender;
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get yield pass factory
     * @return Yield pass factory address
     */
    function yieldPassFactory() external view returns (address) {
        return _yieldPassFactory;
    }

    /*------------------------------------------------------------------------*/
    /* Yield Pass Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint yield token
     * @param to Account
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == _yieldPassFactory, "Unauthorized caller");

        _mint(to, amount);
    }

    /**
     * @notice Burn yield token
     * @param from Account
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == _yieldPassFactory, "Unauthorized caller");

        _burn(from, amount);
    }
}
