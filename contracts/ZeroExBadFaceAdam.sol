// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// Interfaces used to rescue tokens send by mistake (or as spam) to the factory contract address
interface IERC20 { function transfer(address recipient, uint256 amount) external; }
interface IERC721 { function safeTransferFrom(address from, address to, uint256 tokenId) external; }
interface IERC1155 { function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external; }

/// @title The 0xBadFace Meme-PoW Adam Deployer Smart Contract (Adam=0xBadFace1A)
/// @author Tristan Badface (tristan@0xbadface.xyz)
contract ZeroExBadFaceAdam is Ownable(msg.sender), ReentrancyGuard {
    /// @notice Immutable original EOA contract creator address (Eve creator)
    address public constant EVE_CREATOR = 0xBadFace1B0E5d06F4BF9d8fa92B75794fd955781;
    
    /// @notice Data for on-chain foundation paper publication
    string public paper;
    
    /// @notice Data for on-chain project website publication
    string public website;    

    /// @notice Flag to permanently disable the ownership reset function
    bool public contractOwnershipResetDisabled = false;    
    
    /// @notice Emitted when an Eve contract is deployed   
    event EveDeployed(address addr);

    constructor() {
        _transferOwnership(EVE_CREATOR);
    }   

    function deployEve(bytes memory bytecode, uint _salt) external onlyOwner {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        emit EveDeployed(addr);
    }  

    // ------------------------------------------------------------------------
    //                     ETH/Token Rescue from Contract
    // ------------------------------------------------------------------------

    /// @notice Withdraws all ETH accidentally sent to contract
    function withdraw() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
    }

    /// @notice Recovers ERC20 tokens sent to the contract
    /// @param tokenAddress Address of the ERC20 token
    /// @param amount Amount to recover
    function recoverERC20(address tokenAddress, uint256 amount) external nonReentrant onlyOwner {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    /// @notice Recovers ERC721 token sent to the contract
    /// @param tokenAddress Address of the ERC721 token
    /// @param tokenId ID of the token to recover
    function recoverERC721(address tokenAddress, uint256 tokenId) external nonReentrant onlyOwner {
        IERC721(tokenAddress).safeTransferFrom(address(this), owner(), tokenId);
    }

    /// @notice Recovers ERC1155 tokens sent to the contract
    /// @param tokenAddress Address of the ERC1155 token
    /// @param tokenId ID of the token type to recover
    /// @param amount Amount of tokens to recover
    function recoverERC1155(address tokenAddress, uint256 tokenId, uint256 amount) external nonReentrant onlyOwner {
        IERC1155(tokenAddress).safeTransferFrom(address(this), owner(), tokenId, amount, "");
    }

    // ------------------------------------------------------------------------
    //                   Ownership Reset Management
    // ------------------------------------------------------------------------

    /// @notice Allows the original factory creator to reset contract ownership and roles in emergencies
    /// @dev Can be disabled permanently to guard against quantum attacks or transition to community/multisig control.
    function resetContractOwnership() external {
        require(!contractOwnershipResetDisabled, "Reset permanently disabled");
        require(msg.sender == EVE_CREATOR, "Only factory creator can reset");

        _transferOwnership(EVE_CREATOR);
    }

    /// @notice Permanently disables the ownership reset function; irreversible
    /// @param freedomCommand Must equal "Libertas Ex Numeris!" to confirm irreversible action
    function permanentlyDisableContractOwnershipReset(string calldata freedomCommand) external {
        require(msg.sender == EVE_CREATOR, "Only Adam creator can disable");
        require(
            keccak256(abi.encodePacked(freedomCommand)) ==
            keccak256(abi.encodePacked("Libertas Ex Numeris!")),
            "Incorrect command"
        );

        contractOwnershipResetDisabled = true;
    }
    
}
