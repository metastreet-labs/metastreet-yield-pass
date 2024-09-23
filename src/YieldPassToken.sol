// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Yield Token (ERC20)
 * @author MetaStreet Foundation
 */
contract YieldPassToken is ERC20 {
    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Owner
     */
    address internal immutable _owner;

    /*------------------------------------------------------------------------*/
    /* Contructor */
    /*------------------------------------------------------------------------*/

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _owner = msg.sender;
    }

    /*------------------------------------------------------------------------*/
    /* Yield Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint yield token
     * @param to Account
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _mint(to, amount);
    }

    /**
     * @notice Burn yield token
     * @param from Account
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _burn(from, amount);
    }
}
