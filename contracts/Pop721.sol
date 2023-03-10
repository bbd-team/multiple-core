/**
 *Submitted for verification at Etherscan.io on 2019-05-09
 */

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Pop721 is ERC721, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI
    ) ERC721(name, symbol) {
        
    }

    function mint(address to, uint256 tokenId) public virtual onlyOwner {
        _mint(to, tokenId);
    }
}
