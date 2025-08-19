// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IZeroExBadFaceEve {
    function minterMint(address recipient, string memory originalURI) external returns (uint256);
}

contract BadFaceMinterV0 is Ownable(msg.sender), ReentrancyGuard {
    IZeroExBadFaceEve public immutable badFaceNFT;
    
    /// @notice Pre-prepared URIs for minting
    string[] private _tokenURIQueue;
    uint256 private _currentIndex;

    event TokenMinted(uint256 tokenId, string originalURI);
    
    constructor(address nftContract) {
        badFaceNFT = IZeroExBadFaceEve(nftContract);
    } 
    
    /// @notice Adds token URIs before locking
    function addTokenURIs(string[] memory uris) external onlyOwner {
        for (uint256 i = 0; i < uris.length; i++) {
            _tokenURIQueue.push(uris[i]);
        }
    }  

    /// @notice Reset the URIs
    function reset() external onlyOwner {        
        delete _tokenURIQueue;
        _currentIndex = 0;
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
 
    /// @notice Returns the next URI to be minted
    function nextToken() external view returns (string memory) {
        require(_currentIndex < _tokenURIQueue.length, "No tokens to mint");
        return _tokenURIQueue[_currentIndex];
    }    
    
    /// @notice Mints the next NFT in the queue
    function mintNextToken() external nonReentrant onlyOwner {
        require(_currentIndex < _tokenURIQueue.length, "All tokens minted");
        
        string memory uri = _tokenURIQueue[_currentIndex];
        _currentIndex++;
        
        uint256 tokenId = badFaceNFT.minterMint(owner(), uri);
        emit TokenMinted(tokenId, uri);
    }
    
    /// @notice Returns the number of URIs remaining for minting
    function remainingURICount() external view returns (uint256) {
        return _tokenURIQueue.length - _currentIndex;
    }    

}
