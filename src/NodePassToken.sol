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
     * @notice Yield pass factory
     */
    address internal immutable _yieldPassFactory;

    /**
     * @notice Yield pass token
     */
    address internal immutable _yieldPass;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Total supply
     */
    uint256 internal _totalSupply;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice NodePassToken constructor
     * @param name_ Name
     * @param symbol_ Symbol
     * @param yieldPass_ Yield pass token
     */
    constructor(string memory name_, string memory symbol_, address yieldPass_) ERC721(name_, symbol_) {
        _yieldPassFactory = msg.sender;
        _yieldPass = yieldPass_;
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

    /**
     * @notice Get yield pass token
     * @return Yield pass token
     */
    function yieldPass() external view returns (address) {
        return _yieldPass;
    }

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
        require(msg.sender == _yieldPassFactory, "Unauthorized caller");

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
        require(msg.sender == _yieldPassFactory, "Unauthorized caller");

        _burn(tokenId);

        _totalSupply -= 1;
    }
}
