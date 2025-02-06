// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Test Node License
 * @author MetaStreet Foundation
 */
contract TestNodeLicense is ERC721 {
    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Total supply
     */
    uint256 internal _totalSupply;

    /*------------------------------------------------------------------------*/
    /* Contructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice TestNodeLicense constructor
     */
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get total supply
     * @return Total supply
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /*------------------------------------------------------------------------*/
    /* Primary API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint node licenses
     * @param to Account
     * @param count Count
     */
    function mint(address to, uint256 count) external {
        for (uint256 i; i < count; i++) {
            _safeMint(to, _totalSupply + i);
        }

        _totalSupply += count;
    }
}
