// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721, IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

/// @title Interfaces for ERC721 and ERC1155 Token Rescue
/// @notice Interfaces used to rescue tokens accidentally sent to the contract address
interface IERC20 { function transfer(address recipient, uint256 amount) external; }
interface IERC1155 { function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external; }

// -----------------------------------------------------------------------------
// 0xBadFace NFT Contract Summary
//
// 0xBadFace is an NFT collection with:
//   - Its contract and creator address mined via Meme-Proof-of-Work
//   - ERC721 tokens using mutable metadata (with approvals)
//   - Role-based minting and URI control (Admin, Minter, Approver)
//   - EIP-2981 Royalty support with adjustable percentages
//   - URI approval safeguards (hash locking, timing delays, etc.)
//   - Optional ownership reset mechanism (Eve Creator), permanently lockable
//
// -----------------------------------------------------------------------------

/// @title The 0xBadFace Meme-PoW NFT Smart Contract (Eve=0xBadFace1E)
/// @author Tristan Badface (tristan@0xbadface.xyz)
/// @notice ERC721 NFT contract featuring mutable metadata URIs, role-based minting, EIP-2981 royalties, and meme-PoW address.
/// @dev Implements IERC2981, IERC4906, Ownable, and ReentrancyGuard.
contract ZeroExBadFaceEve is ERC721("0xBadFace", "0xBFE"), IERC2981, IERC4906, Ownable(msg.sender), ReentrancyGuard {
    /// @notice Maximum number of NFTs that can be minted
    uint256 public constant MAX_SUPPLY = 10000;

    /// @dev Counter for minted token IDs
    uint256 private _tokenIds;

    /// @dev Royalty percentage (0–100%)
    uint256 private _royaltyPercentage;

    /// @dev Address that receives royalty payments
    address private _royaltyRecipient;

    /// @notice Admin role, can manage most settings except ownership transfer
    address public admin;

    /// @notice Minter role, authorized to mint NFTs
    address public minter;

    /// @notice Approver role, authorized to approve metadata changes
    address public approver;

    /// @notice Maximum number of tokens the minter can mint
    uint256 public minterMintingLimit;

    /// @dev Counter for tokens minted by the minter
    uint256 public minterMintedCount;

    /// @dev Timestamp of last mint action by the minter
    uint256 public lastMintTimestamp;

    /// @notice Minimum delay between mints (in seconds)
    uint256 public constant MINT_DELAY = 60;

    /// @notice Maximum allowed length for user-proposed URIs
    uint256 public maxUserURILength = 256;

    /// @notice Flag to allow or disallow token owners to self-approve their URI changes
    bool public userApproveChangeEnabled = false;

    /// @notice Flag to allow or disallow token owners to revert to original URI themselves
    bool public revertToOriginalURIEnabled = false;

    /// @notice Required minimum delay between a user URI change and its approval, prevents front-running (default 1 hour)
    uint256 public userURIApprovalWindow = 60 minutes;

    /// @notice Flag requiring hashed change locks for approver — when true, approver must provide matching keccak256(currentURI, userURI)
    bool public requireChangeHashes = true;

    /// @notice Immutable original EOA contract creator address (Eve creator)
    address public constant EVE_CREATOR = 0xBadFace1B0E5d06F4BF9d8fa92B75794fd955781;

    /// @notice Flag to permanently disable the ownership reset function
    bool public contractOwnershipResetDisabled = false;

    /// @notice URI for contract-level metadata, used by OpenSea and other marketplaces/analytics
    string public contractURI_;

    /// @dev Structure holding all URI variants for a token
    struct TokenURIData {
        string originalURI;  // Immutable original URI
        string userURI;      // User-proposed URI pending approval
        string currentURI;   // Active metadata URI
    }

    /// @dev Mapping from token ID to its metadata structure
    mapping(uint256 => TokenURIData) private _tokenURIs;

    /// @dev Mapping from token ID to timestamp of last user URI change
    mapping(uint256 => uint256) private _lastUserURIChange;

    /// @notice Emitted when a new token is minted
    event BadFaceMinted(uint256 indexed tokenId, string originalURI);

    /// @notice Emitted when one or more tokens have their active URI updated
    event BadFaceChanged(uint256[] approvedTokenIds);

    /// @notice Emitted once when contract ownership reset is permanently disabled, indicating full transition away from centralized control
    event BadFaceLibertasExNumeris(address indexed currentContractOwner);

    /// @notice Emitted when the contract-level metadata URI is updated
    event ContractURIUpdated();

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not the admin");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller is not the minter");
        _;
    }

    modifier onlyApprover() {
        require(msg.sender == approver, "Caller is not the approver");
        _;
    }

    constructor() {
        _transferOwnership(EVE_CREATOR);
        _royaltyRecipient = EVE_CREATOR;
        _royaltyPercentage = 5;
    }

    /// @notice Sets or clears the admin role; resets minter, approver, and royalties to owner
    /// @param newAdmin Address to grant admin role, or zero to remove
    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
        minter = address(0);
        approver = address(0);
        _royaltyRecipient = owner();
    }

    // ------------------------------------------------------------------------
    //                             Contract URI
    // ------------------------------------------------------------------------

    /// @notice Returns the URI for contract-level metadata (OpenSea, marketplaces, analytics)
    /// @return URI as a string
    function contractURI() public view returns (string memory) {
        return contractURI_;
    }

    /// @notice Sets the contract-level metadata URI for marketplaces and analytics tools
    /// @param newContractURI New metadata URI
    function setContractURI(string calldata newContractURI) external onlyAdmin {
        contractURI_ = newContractURI;
        emit ContractURIUpdated();
    }

    // ------------------------------------------------------------------------
    //                      Token URI Management
    // ------------------------------------------------------------------------

    /// @notice Returns the active metadata URI for a token
    /// @param tokenId Token ID to query
    /// @return The currentURI string
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "URI query for nonexistent token");
        return _tokenURIs[tokenId].currentURI;
    }

    /// @notice Returns the original, immutable metadata URI for a token
    /// @param tokenId Token ID to query
    /// @return The originalURI string
    function tokenOriginalURI(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "URI query for nonexistent token");
        return _tokenURIs[tokenId].originalURI;
    }

    /// @notice Allows the token owner to propose a new metadata URI (stored in userURI)
    /// @param tokenId Token ID to update
    /// @param newUserURI New user-proposed URI (max length enforced)
    function setUserURI(uint256 tokenId, string calldata newUserURI) external {
        require(msg.sender == _ownerOf(tokenId), "Caller is not the token owner");
        require(bytes(newUserURI).length <= maxUserURILength, "User URI too long");
        _tokenURIs[tokenId].userURI = newUserURI;
        _lastUserURIChange[tokenId] = block.timestamp;
    }

    /// @notice Returns timestamp of the last user URI change
    /// @param tokenId Token ID to query
    /// @return Timestamp of last change
    function getLastUserURIChange(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Query for nonexistent token");
        return _lastUserURIChange[tokenId];
    }

    /// @notice Retrieves all URI data for a token; sanitize output to prevent XSS
    /// @param tokenId Token ID to query
    /// @return TokenURIData struct containing originalURI, userURI, currentURI
    function unsafeGetTokenURIStorageData(uint256 tokenId) external view returns (TokenURIData memory) {
        require(_ownerOf(tokenId) != address(0), "Query for nonexistent token");
        return _tokenURIs[tokenId];
    }

    /// @notice Sets a new maximum length for user-proposed URIs
    /// @param newMaxLength New max length
    function setMaxUserURILength(uint256 newMaxLength) external onlyAdmin {
        maxUserURILength = newMaxLength;
    }

    // ------------------------------------------------------------------------
    //                                Minting
    // ------------------------------------------------------------------------

    /// @notice Assigns the minter role and sets its minting limit
    /// @param _minter Address to grant minter role
    /// @param _limit Maximum tokens the minter can mint
    function setMinter(address _minter, uint256 _limit) external onlyAdmin {
        minter = _minter;
        minterMintingLimit = _limit;
        minterMintedCount = 0;
    }

    /// @notice Minter-only function to mint a new token with given originalURI
    /// @param recipient Address to receive the minted token
    /// @param originalURI Metadata URI for the new token
    /// @return newItemId Newly minted token ID
    function minterMint(address recipient, string memory originalURI) external onlyMinter returns (uint256) {
        require(_tokenIds < MAX_SUPPLY, "Max supply reached");
        require(minterMintedCount < minterMintingLimit, "Minter limit reached");
        require(block.timestamp >= lastMintTimestamp + MINT_DELAY, "Minting too soon");

        _tokenIds++;
        uint256 newItemId = _tokenIds;
        _safeMint(recipient, newItemId);

        _tokenURIs[newItemId] = TokenURIData({
            originalURI: originalURI,
            userURI: "",
            currentURI: originalURI
        });

        minterMintedCount++;
        lastMintTimestamp = block.timestamp;

        emit BadFaceMinted(newItemId, originalURI);
        return newItemId;
    }

    // ------------------------------------------------------------------------
    //                URI Change Approval (Approver) Settings
    // ------------------------------------------------------------------------

    /// @notice Sets the minimum delay (in seconds) after a user URI change before approval allowed
    /// @param newWindow New delay window in seconds
    function setApprovalWindow(uint256 newWindow) external onlyAdmin {
        userURIApprovalWindow = newWindow;
    }

    /// @notice Assigns the approver role
    /// @param _approver Address to grant approver role
    function setApprover(address _approver) external onlyAdmin {
        approver = _approver;
    }

    /// @notice Toggles whether approver must supply changeHashes to guard against front-running
    function flipChangeHashesRequirement() external onlyAdmin {
        requireChangeHashes = !requireChangeHashes;
    }

    /// @notice Approver approves or rejects multiple pending userURI updates with optional hash-lock protection
    /// @param tokenIds Array of token IDs to approve
    /// @param changeHashes Array of keccak256(currentURI, userURI) hashes matching each token (required if requireChangeHashes is True)
    /// @return failedIds Array of token IDs that failed approval checks
    function approverApproveChanges(
        uint256[] calldata tokenIds,
        bytes32[] calldata changeHashes
    ) external onlyApprover returns (uint256[] memory) {
        require(!requireChangeHashes || changeHashes.length > 0, "Hashed changes list required");
        require(changeHashes.length == 0 || tokenIds.length == changeHashes.length, "Length mismatch");

        bool checkHashes = (tokenIds.length == changeHashes.length);
        uint256[] memory approvedIds = new uint256[](tokenIds.length);
        uint256[] memory failedIds   = new uint256[](tokenIds.length);
        uint256 approvedCount = 0;
        uint256 failedCount   = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            TokenURIData storage data = _tokenURIs[tokenIds[i]];
            if (
                bytes(data.userURI).length == 0 ||
                block.timestamp < _lastUserURIChange[tokenIds[i]] + userURIApprovalWindow ||
                (checkHashes &&
                 keccak256(abi.encodePacked(data.currentURI, data.userURI)) != changeHashes[i])
            ) {
                failedIds[failedCount++] = tokenIds[i];
                continue;
            }
            data.currentURI = data.userURI;
            delete data.userURI;
            approvedIds[approvedCount++] = tokenIds[i];
            emit MetadataUpdate(tokenIds[i]);
        }

        if (approvedCount > 0) {
            uint256[] memory trimmed = new uint256[](approvedCount);
            for (uint256 j = 0; j < approvedCount; j++) trimmed[j] = approvedIds[j];
            emit BadFaceChanged(trimmed);
        }

        if (failedCount > 0) {
            uint256[] memory trimmed = new uint256[](failedCount);
            for (uint256 k = 0; k < failedCount; k++) trimmed[k] = failedIds[k];
            return trimmed;
        }
        
        uint256[] memory empty = new uint256[](1);
        empty[0] = 0;
        return empty;
    }

    // ------------------------------------------------------------------------
    //                   Token Owner URI Self-Approval
    // ------------------------------------------------------------------------

    /// @notice Toggles whether token owners can self-approve their URI changes
    function flipUserApproveChangePermission() external onlyOwner {
        userApproveChangeEnabled = !userApproveChangeEnabled;
    }

    /// @notice Allows token owner to apply their proposed userURI if self-approval is enabled
    /// @param tokenId Token ID to update
    function userApproveChange(uint256 tokenId) external {
        require(userApproveChangeEnabled, "Users cannot self-approve");
        require(msg.sender == _ownerOf(tokenId), "Caller is not token owner");
        TokenURIData storage data = _tokenURIs[tokenId];
        require(bytes(data.userURI).length > 0, "User URI not set");
        require(
            keccak256(abi.encodePacked(data.currentURI)) != keccak256(abi.encodePacked(data.userURI)),
            "Nothing to change"
        );
        data.currentURI = data.userURI;
        delete data.userURI;

	uint256[] memory single = new uint256[](1);
        single[0] = tokenId;
        emit BadFaceChanged(single);
        emit MetadataUpdate(tokenId);
    }

    // ------------------------------------------------------------------------
    //                 Token Owner Revert to Original URI
    // ------------------------------------------------------------------------

    /// @notice Toggles whether token owners can revert to the original URI themselves
    function flipUserRevertToOriginalURIPermission() external onlyOwner {
        revertToOriginalURIEnabled = !revertToOriginalURIEnabled;
    }

    /// @notice Allows token owner to revert currentURI back to originalURI if enabled
    /// @param tokenId Token ID to revert
    function userRevertToOriginalURI(uint256 tokenId) external {
        require(revertToOriginalURIEnabled, "Self-revert not enabled");
        require(msg.sender == _ownerOf(tokenId), "Caller is not the token owner");
        TokenURIData storage data = _tokenURIs[tokenId];
        require(
            keccak256(abi.encodePacked(data.currentURI)) != keccak256(abi.encodePacked(data.originalURI)),
            "Nothing to revert"
        );
        data.currentURI = data.originalURI;

	uint256[] memory single = new uint256[](1);
        single[0] = tokenId;
        emit BadFaceChanged(single);
        emit MetadataUpdate(tokenId);
    }

    // ------------------------------------------------------------------------
    //                              Royalties
    // ------------------------------------------------------------------------

    /// @inheritdoc IERC2981
    /// @notice Returns the royalty recipient and amount for a sale price
    /// @param  tokenId Token ID (ignored)
    /// @param  salePrice Sale price
    /// @return receiver Address to receive royalties
    /// @return royaltyAmount Calculated royalty amount
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        require(_ownerOf(tokenId) != address(0), "Query for nonexistent token");    
        royaltyAmount = (salePrice * _royaltyPercentage) / 100;
        return (_royaltyRecipient, royaltyAmount);
    }

    /// @notice Sets a new royalty percentage (max 20%)
    /// @param percentage Royalty percentage to set
    function setRoyaltyPercentage(uint256 percentage) external onlyAdmin {
        require(percentage <= 20, "Percentage too high");
        _royaltyPercentage = percentage;
    }

    /// @notice Sets a new recipient address for royalties
    /// @param recipient New royalty recipient
    function setRoyaltyRecipient(address recipient) external onlyAdmin {
        _royaltyRecipient = recipient;
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
        minter = address(0);
        approver = EVE_CREATOR;
        _royaltyRecipient = EVE_CREATOR;
    }

    /// @notice Permanently disables the ownership reset function; irreversible
    /// @param freedomCommand Must equal "Libertas Ex Numeris!" to confirm irreversible action
    function permanentlyDisableContractOwnershipReset(string calldata freedomCommand) external {
        require(msg.sender == EVE_CREATOR, "Only Eve creator can disable");
        require(
            keccak256(abi.encodePacked(freedomCommand)) ==
            keccak256(abi.encodePacked("Libertas Ex Numeris!")),
            "Incorrect command"
        );

        contractOwnershipResetDisabled = true;
        emit BadFaceLibertasExNumeris(owner());
    }

    // ------------------------------------------------------------------------
    //                           Burning Tokens
    // ------------------------------------------------------------------------

    /// @notice Burns a token, removing it and freeing storage
    /// @param tokenId Token ID to burn
    function burn(uint256 tokenId) external {
        require(msg.sender == _ownerOf(tokenId), "Caller is not the token owner");
        _burn(tokenId);
        delete _tokenURIs[tokenId];
        delete _lastUserURIChange[tokenId];
    }

    // ------------------------------------------------------------------------
    //                         Interface Support
    // ------------------------------------------------------------------------

    /// @inheritdoc IERC165
    /// @notice Indicates support for ERC721, IERC4906, and IERC2981
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IERC4906).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

