// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


contract MyToken is ERC721, ERC721Enumerable, ERC721Pausable, Ownable, ERC721Burnable,ERC721Royalty,ReentrancyGuard {

    error SupplyNotAvailable();
    error InvalidPhase();
    error InvalidPhaseLength();
    error AlreadyAllocated();
    error LastPhaseAlreadyStarted();
    error InsufficientPayment();
    error InvalidProof();
    error InvalidTokenID();
    error MintAllowanceExceeded();
    error InvalidFundsReceiver();
    error TransferFailed();

    event FundsWithdrawn(address indexed receiver);

    uint256 private _nextTokenId;
    string public baseUri;

    address public fundsReceiver;
    uint256 public totalFunds;

    uint256 public mintedSupply;
    uint256 public maxMintableSupply;

    bool public reallocated;

    struct MintPhase {
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint256 mintableSupply;
        uint256 maxMintPerWallet;
        bytes32 merkleRoot;
    }

    MintPhase[] public mintPhases;
    mapping(uint256 => uint256) public phaseMintedSupply;
    mapping(uint256 => mapping(address => uint256)) public phaseWalletMintedCount;

    modifier hasSupply(uint256 phaseIndex, uint256 quantity) {
        MintPhase memory phase = mintPhases[phaseIndex];
  
        if (
            phase.mintableSupply > 0 &&
            phaseMintedSupply[phaseIndex] + quantity > phase.mintableSupply
        ) {
            revert SupplyNotAvailable();
        }
  
        if (
            maxMintableSupply > 0 &&
            totalSupply() + quantity > maxMintableSupply
        ) {
            revert SupplyNotAvailable();
        }
        _;
    }

    modifier isValidPhase(uint256 phaseIndex) {
        if (phaseIndex >= mintPhases.length) {
            revert InvalidPhase();
        }
  
        MintPhase memory phase = mintPhases[phaseIndex];
  
        if (
            block.timestamp < phase.startTime || block.timestamp > phase.endTime
        ) {
            revert InvalidPhase();
        }
 
        _;
    }

    modifier isValidTokenId(uint256 tokenId){
        if(_ownerOf(tokenId) == address(0)){
            revert InvalidTokenID();
        }
        _;
    }

    constructor(string memory name, string memory symbol, string memory _baseUri, address _royalityReceiver, uint96 _royalityPercent, address _fundsReceiver, uint256 _maxMintableSupply)
        ERC721(name, symbol)
        Ownable(msg.sender)
    {
        if (_fundsReceiver == address(0)) {
            revert InvalidFundsReceiver();
        }

        _setDefaultRoyalty(_royalityReceiver, _royalityPercent); // 5% royalty (500 basis points)
        baseUri=_baseUri;
        fundsReceiver=_fundsReceiver;
        maxMintableSupply=_maxMintableSupply;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
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

    function setMintPhases(MintPhase[] calldata newPhases) external onlyOwner {
        delete mintPhases;
        for (uint256 i = 0; i < newPhases.length; i++) {
            if (newPhases[i].startTime > newPhases[i].endTime) {
                revert InvalidPhase();
            }
            mintPhases.push(newPhases[i]);
        }
    }

    function mint(uint256 phaseIndex, bytes32[] calldata merkleProof, uint256 allowedMints, uint256 quantity)
        external
        payable
        isValidPhase(phaseIndex)
        hasSupply(phaseIndex, quantity) 
        whenNotPaused
        nonReentrant
    {
        MintPhase memory phase = mintPhases[phaseIndex];

        if (phase.merkleRoot != bytes32(0)) {
            validateMerkleProof(merkleProof, phase.merkleRoot, allowedMints);
 
            if (
                allowedMints > 0 &&
                phaseWalletMintedCount[phaseIndex][msg.sender] + quantity >
                allowedMints
            ) {
                revert MintAllowanceExceeded();
            }
        } else if (phase.maxMintPerWallet > 0 && phaseWalletMintedCount[phaseIndex][msg.sender] + quantity > phase.maxMintPerWallet) {
            revert MintAllowanceExceeded();
        }

        if(msg.value < phase.price * quantity){
            revert InsufficientPayment();
        }

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }

        totalFunds += phase.price * quantity;
        mintedSupply += quantity;
        phaseMintedSupply[phaseIndex] += quantity;
        phaseWalletMintedCount[phaseIndex][msg.sender] += quantity;
    }

    function validateMerkleProof(
        bytes32[] calldata merkleProof,
        bytes32 merkleRoot,
        uint256 allowedMints
    ) internal view {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, allowedMints));
        bool valid = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        if (!valid) {
            revert InvalidProof();
        }
    }

    function reallocatePendingSupplyToLastPhase() external onlyOwner {
        if(reallocated){
            revert AlreadyAllocated();
        }

        if(block.timestamp > mintPhases[mintPhases.length - 1].startTime){
            revert LastPhaseAlreadyStarted();
        }

        if(mintPhases.length <= 1){
            revert InvalidPhaseLength();
        }

        uint256 totalPending = 0;

        // Accumulate unused supply from all phases except the last
        for (uint256 i = 0; i < mintPhases.length - 1; i++) {
            uint256 minted = phaseMintedSupply[i];
            uint256 supply = mintPhases[i].mintableSupply;

            if (supply > minted) {
                totalPending += (supply - minted);
            }
        }

        // Add the pending supply to the last phase
        if(totalPending > 0){
            MintPhase storage lastPhase = mintPhases[mintPhases.length - 1];
            lastPhase.mintableSupply += totalPending;   
        }
    }

    function withdraw() public onlyOwner nonReentrant {
        (bool success, ) = fundsReceiver.call{value: totalFunds}("");
        if(!success){
            revert TransferFailed();
        }
        emit FundsWithdrawn(fundsReceiver);
    }

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
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
        return string(abi.encodePacked(baseUri, "/", Strings.toString(tokenId), ".json"));
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