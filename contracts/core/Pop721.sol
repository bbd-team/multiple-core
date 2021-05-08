/**
 *Submitted for verification at Etherscan.io on 2019-05-09
 */

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/WhiteList.sol";

contract Pop721 is ERC721, ERC721Burnable, ERC721Holder, WhiteList {
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI
    ) public ERC721(name, symbol) {
        _setBaseURI(baseURI);
    }

    function mint(address to, uint256 tokenId) public virtual onlyWhitelisted {
        _mint(to, tokenId);
    }

    function setBaseURI(string memory newBaseUri) public virtual requireImpl {
        _setBaseURI(newBaseUri);
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        public
        virtual
        requireImpl
    {
        super._setTokenURI(tokenId, _tokenURI);
    }
}
