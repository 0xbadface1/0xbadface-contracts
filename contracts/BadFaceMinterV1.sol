// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IZeroExBadFaceEveNFT {
    function minterMint(address recipient, string memory originalURI) external returns (uint256);
}

contract BadFaceMinterV1 is Ownable(msg.sender), ReentrancyGuard {
    IZeroExBadFaceEveNFT public immutable badFaceNFT;
    
    /// @notice Pre-prepared URIs for minting
    string[] private _tokenURIQueue;
    uint256 private _currentIndex;
    bool public isLocked = false;
    uint256 public lockCheckTimestamp;
    /// @notice Admin role, can manage (most) settings but cannot transfer ownership
    address public unlocker;
    bool unlockerChecked = false;
    address public tokenDestination;
    uint256 public foreignTokenDestinationDeposit = 0;
    uint256 public lastMintTimestamp;
    uint256 public constant MINT_DELAY = 60; // 1 minute delay per mint
    uint256 public constant LOCK_DELAY = 20 minutes; // 20 minutes delay after unlocker check

    event MinterLocked();
    event MinterChecked_ReadyIn20Minutes();
    event MinterUnlocked();
    event TokenMinted(uint256 tokenId, string originalURI);
    event DepositReceived(address indexed from, uint256 amount);
    
    constructor(address nftContract, address nftAdmin) {
        badFaceNFT = IZeroExBadFaceEveNFT(nftContract);
        unlocker = nftAdmin;
        tokenDestination = owner();
    } 
    
    /// @notice Adds token URIs before locking
    function addTokenURIs(string[] memory uris) external onlyOwner {
        require(!isLocked, "Already locked");

        for (uint256 i = 0; i < uris.length; i++) {
            _tokenURIQueue.push(uris[i]);
        }
    }  

    /// @notice Rest the URIs before locking happened
    function resetURIs() external onlyOwner {
        require(!isLocked, "Already locked");
        
        delete _tokenURIQueue;
        _currentIndex = 0;
    }

    function setTokenDestination(address destination) external onlyOwner {
        require(!isLocked, "Already locked");
        require(destination != address(0), "Token destination cannot be null address.");

        tokenDestination = destination;    
        foreignTokenDestinationDeposit = 0;
    }     

    /// @notice Accept direct ETH deposits and verify sender matches token destination
    receive() external payable {
        if (msg.sender == tokenDestination && msg.value > 0) {
            foreignTokenDestinationDeposit += msg.value;
            emit DepositReceived(msg.sender, msg.value);
        }
    }    

    /// @notice Locks the URIs, preventing further modification
    function lock() external onlyOwner {
        require(!isLocked, "Already locked");
        require(unlockerChecked, "Unlocker did not check the configuration");
        require(_tokenURIQueue.length > 0, "No URIs to lock");
        require(unlocker != address(0), "Unlocker cannot be null address.");


        isLocked = true;
        emit MinterLocked();
    }

    /// @notice Returns the list of URIs remaining for minting
    function getURIsForMinting() external view returns (string[] memory) {
        uint256 remaining = _tokenURIQueue.length - _currentIndex;
        string[] memory uris = new string[](remaining);
        for (uint256 i = 0; i < remaining; i++) {
            uris[i] = _tokenURIQueue[_currentIndex + i];
        }
        return uris;
    }   

    /// @notice Only callable by unlocker to confirm all config
    function unlockerCheck() external returns (uint256, address) {
        require(msg.sender == unlocker, "Caller is not the Unlocker");
        require(isLocked, "Not locked");

        unlockerChecked = true;
        lockCheckTimestamp = block.timestamp;
        
        emit MinterChecked_ReadyIn20Minutes();

        uint256 remaining = _tokenURIQueue.length - _currentIndex;
        return (remaining, tokenDestination);
    }  

   

    /// @notice Returns the next URI to be minted
    function nextToken() external view returns (string memory) {
        require(_currentIndex < _tokenURIQueue.length, "No tokens to mint");
        return _tokenURIQueue[_currentIndex];
    }    
    
    /// @notice Mints the next NFT in the queue
    function mintNextToken() external nonReentrant onlyOwner {
        require(isLocked, "Contract must be locked before minting.");
        require(tokenDestination == owner() || foreignTokenDestinationDeposit > 0, "Token destination did not confirm it has control.");
        require(block.timestamp >= lockCheckTimestamp + LOCK_DELAY, "Wait at least 20 minutes after checking the locked state before starting minting.");
        require(_currentIndex < _tokenURIQueue.length, "All tokens minted");
        require(block.timestamp >= lastMintTimestamp + MINT_DELAY, "Wait at least 1 minute between mints.");
        
        string memory uri = _tokenURIQueue[_currentIndex];
        _currentIndex++;
        lastMintTimestamp = block.timestamp;
        
        uint256 tokenId = badFaceNFT.minterMint(owner(), uri);
        emit TokenMinted(tokenId, uri);
    }
    

    
    /// @notice Returns the number of URIs remaining for minting
    function remainingURICount() external view returns (uint256) {
        return _tokenURIQueue.length - _currentIndex;
    }    

    /// @notice Unlocks and resets the queue (usually after minting), only callable by unlocker
    function unlockAndReset() external {
        require(msg.sender == unlocker, "Caller is not the Unlocker");
        require(isLocked, "Not locked");

        delete _tokenURIQueue;
        _currentIndex = 0;

        unlockerChecked = false;

        tokenDestination = owner();
        foreignTokenDestinationDeposit = 0;

        lockCheckTimestamp = 0;
        isLocked = false;

        emit MinterUnlocked();
    }

    function withdraw() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
    } 

}
