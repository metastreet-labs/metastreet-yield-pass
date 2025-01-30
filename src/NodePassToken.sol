// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Node Pass Token (ERC721)
 * @author MetaStreet Foundation
 */
contract NodePassToken is ERC721 {
    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Owner
     */
    address internal immutable _owner;

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
     * @notice NodePassToken constructor
     */
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        _owner = msg.sender;
    }

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
    /* Node Pass Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint node tokens
     * @param to Account
     * @param tokenIds Token IDs
     */
    function mint(address to, uint256[] calldata tokenIds) external {
        require(msg.sender == _owner, "Unauthorized caller");

        for (uint256 i; i < tokenIds.length; i++) {
            _mint(to, tokenIds[i]);
        }

        _totalSupply += tokenIds.length;
    }

    /**
     * @notice Burn node token
     * @param tokenId Token ID
     */
    function burn(
        uint256 tokenId
    ) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _burn(tokenId);

        _totalSupply -= 1;
    }
}
