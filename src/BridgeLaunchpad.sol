// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract BridgeLaunchpad is ERC721, ERC721Enumerable, ERC721Pausable, Ownable, ERC721Burnable,ReentrancyGuard,ERC721Royalty {

    error SupplyNotAvailable();
    error InvalidTokenID();
    error InvalidMintSupply();

    uint256 supply;
    uint256 mintedSupply;

    string private baseUri;

    modifier isValidTokenId(uint256 tokenId){
        if(_ownerOf(tokenId) == address(0)){
            revert InvalidTokenID();
        }
        _;
    }

    modifier hasSupplyAvailable{
        if(mintedSupply>=supply){
            revert SupplyNotAvailable();
        }
        _;
    }

    constructor(string memory name, string memory symbol, string memory _baseUri, uint256 _maxMintableSupply, address _royaltyReceiver, uint96 _royaltyPercent)
        ERC721(name, symbol)
        Ownable(msg.sender)
    {
        if (_maxMintableSupply == 0) {
            revert InvalidMintSupply();
        }

        baseUri=_baseUri;
        supply=_maxMintableSupply;
        _setDefaultRoyalty(_royaltyReceiver, _royaltyPercent);
    }

    function setBaseURI(string memory _baseUri) external onlyOwner(){
        baseUri=_baseUri;
    }

    function setMaxMintableSupply(uint256 _maxMintableSupply) external onlyOwner {
        if (_maxMintableSupply == 0 || _maxMintableSupply < mintedSupply) {
            revert InvalidMintSupply();
        }
        supply = _maxMintableSupply;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address receiver, uint256 tokenId)
        external
        payable
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        _safeMint(receiver, tokenId);
        mintedSupply += 1;
    }

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        isValidTokenId(tokenId)
        view
        override(ERC721)
        returns (string memory)
    {
        return string(abi.encodePacked(baseUri, "/", Strings.toString(tokenId)));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable,ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}

    fallback() external payable {}
}