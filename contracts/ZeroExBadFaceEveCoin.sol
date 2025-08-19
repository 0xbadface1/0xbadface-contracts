// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Interfaces for ERC721 and ERC1155 Token Rescue
/// @notice Interfaces used to rescue tokens accidentally sent to the contract address
interface IERC721 { function safeTransferFrom(address from, address to, uint256 tokenId) external; }
interface IERC1155 { function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external; }

/**
 * @title The 0xBadFace Meme-PoW Coin Smart Contract (Eve=0xBadFace1C)
 * @author Tristan Badface (tristan@0xbadface.xyz)
 * @notice ERC20 token with capped supply, minting, burning, and meme-PoW address.
 * @dev Standard ERC20 extended with Ownable mint control and rescue functions for trapped assets.
 */
contract ZeroExBadFaceEveCoin is ERC20("0xBadFace Coin", "0xBFC"), Ownable(msg.sender), ReentrancyGuard {
    /// @notice Maximum supply cap of 10 billion tokens (with 18 decimals)
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10**18;

    /// @notice Immutable original EOA contract creator address (Eve creator)
    address public constant EVE_CREATOR = 0xBadFace1B0E5d06F4BF9d8fa92B75794fd955781;

    /**
     * @notice Initializes the ERC20 contract and transfers ownership to Eve creator
     */
    constructor() {
        _transferOwnership(EVE_CREATOR);
    }

    /**
     * @notice Mints new tokens to a specified address.
     * @dev Only callable by the contract owner. Cannot exceed MAX_SUPPLY.
     * @param to Address to receive the minted tokens.
     * @param amount Number of tokens to mint (in whole units, without considering decimals).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount * 10**decimals() <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount * 10**decimals());
    }

    /**
     * @notice Burns a specified amount of caller's tokens.
     * @dev Callable by any token holder.
     * @param amount Number of tokens to burn (in whole units, without considering decimals).
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount * 10**decimals());
    }

    /**
     * @notice Withdraws any ETH accidentally sent to the contract.
     * @dev Only callable by the contract owner. Uses nonReentrant modifier to prevent reentrancy attacks.
     */
    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Recovers ERC20 tokens sent to the contract by mistake.
     * @dev Only callable by the contract owner.
     * @param tokenAddress Address of the ERC20 token contract.
     * @param amount Amount of tokens to recover (in smallest units).
     */
    function recoverERC20(address tokenAddress, uint256 amount) external onlyOwner nonReentrant {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    /**
     * @notice Recovers an ERC721 token sent to the contract by mistake.
     * @dev Only callable by the contract owner.
     * @param tokenAddress Address of the ERC721 token contract.
     * @param tokenId ID of the token to recover.
     */
    function recoverERC721(address tokenAddress, uint256 tokenId) external onlyOwner nonReentrant {
        IERC721(tokenAddress).safeTransferFrom(address(this), owner(), tokenId);
    }

    /**
     * @notice Recovers ERC1155 tokens sent to the contract by mistake.
     * @dev Only callable by the contract owner.
     * @param tokenAddress Address of the ERC1155 token contract.
     * @param tokenId ID of the token type to recover.
     * @param amount Amount of tokens to recover.
     */
    function recoverERC1155(address tokenAddress, uint256 tokenId, uint256 amount) external onlyOwner nonReentrant {
        IERC1155(tokenAddress).safeTransferFrom(address(this), owner(), tokenId, amount, "");
    }
}

