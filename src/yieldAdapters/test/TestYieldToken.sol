// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Test Yield Token
 * @author MetaStreet Foundation
 */
contract TestYieldToken is ERC20, AccessControl {
    /*------------------------------------------------------------------------*/
    /* Access Control Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint role
     */
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice TestYieldToken constructor
     * @notice name Token name
     * @notice symbol Token symbol
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Primary API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint yield token
     * @param to Account
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burn yield token
     * @param from Account
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyRole(MINT_ROLE) {
        _burn(from, amount);
    }
}
