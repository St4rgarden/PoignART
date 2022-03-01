// SPDX-License-Identifier: MIT
// @author Kyle_Stargarden w/ Big thanks to yusefnapora
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract YourContract is ERC721, EIP712, ERC721URIStorage, Pausable, AccessControl {

    using ECDSA for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CRON_JOB = keccak256("CRON_JOB");
    address public constant UNCHAIN = 0x10E1439455BD2624878b243819E31CfEE9eb721C;
    address public constant UKRAINEDAO = 0x633b7218644b83D57d90e7299039ebAb19698e9C;

    constructor() ERC721("Poignard", "[]++++||=======>") EIP712("PoignardVoucher", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(CRON_JOB, msg.sender);
    }

    /*************************
     MAPPING STRUCTS EVENTS
     *************************/

    // voucher object is signed and stored off-chain to enable and enforce lazy minting
    struct NFTVoucher {

        // @notice The id of the token to be redeemed. Must be unique - if another token with this ID already exists, the redeem function will revert.
        uint256 tokenId;
        // @notice The minimum price (in wei) that the NFT creator is willing to accept for the initial sale of this NFT.
        uint256 minPrice;
        // @notice The metadata URI to associate with this token.
        string uri;

    }

    // event allows indexing of artists who have gained MINTER_ROLE and for which _merkleRoot version
    event Vetted (
        // @notice The address of the vetted artist
        address artist,
        // @notice The merkleRoot that they used for authentication
        bytes32 _merkleRoot

        );

    /*************************
     STATE VARIABLES
     *************************/

    // the _merkleRoot allowing authentication of all users from snapshot and community vetting
    bytes32 public _merkleRoot;

    /*************************
     MODIFIERS
     *************************/

    // prevents all contracts from calling the minting functions
    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract!");
        _;
    }

    /*************************
     VIEW AND PURE FUNCTIONS
     *************************/

    // view function returns true if an artist address is part of the merkleTree
    function _verifyArtist(

        address _artist,

        bytes32[] memory _merkleProof
    )
        public
        view
        returns (bool valid) {

        bytes32 _leaf = keccak256(abi.encodePacked(_artist));

        return MerkleProof.verify(_merkleProof, _merkleRoot, _leaf);

    }

    // view function returns the base token URI slug
    function _baseURI() internal pure override returns (string memory) {
        return "https://creatorsforukraine.io/";
    }

    /*************************
     USER FUNCTIONS
     *************************/

    // function authenticates artists through the merkle tree and assigns MINTER_ROLE
    function vetArtist(

        address artist,

        bytes32[] memory _merkleProof
    )
        public
        whenNotPaused {

        require(_msgSender() == artist, "Artists have to add themselves!");
        require(_verifyArtist(artist, _merkleProof), "Not authorized!");
        _grantRole(MINTER_ROLE, artist);
        emit Vetted(artist, _merkleRoot);

    }

    function redeem(
        address redeemer,
        NFTVoucher calldata voucher,
        bytes memory signature
    )
        public
        payable
        callerIsUser
        whenNotPaused
        returns (uint256) {

    // make sure signature is valid and get the address of the signer
    address signer = _verify(voucher, signature);

    // make sure that the signer is authorized to mint NFTs
    require(hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= voucher.minPrice, "Insufficient funds to redeem");

    // first assign the token to the signer, to establish provenance on-chain
    _mint(signer, voucher.tokenId);
    _setTokenURI(voucher.tokenId, voucher.uri);

    // transfer the token to the redeemer
    _transfer(signer, redeemer, voucher.tokenId);

    return voucher.tokenId;
  }


    /*************************
     ACCESS CONTROL FUNCTIONS
     *************************/

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function cronJobRoot(
        bytes32 newRoot
    )
        external onlyRole(CRON_JOB) {
        _merkleRoot = newRoot;
    }

    /** @dev Function for withdrawing ETH to UkraineDAO and Unchain
    * Constants are used for transparency and safety
    */
    function withdrawAll()
        public
        onlyRole(CRON_JOB)
    {
        uint balanceLessGas = address(this).balance - tx.gasprice;
        uint half = balanceLessGas / 2;
        require(payable(UNCHAIN).send(half));
        require(payable(UKRAINEDAO).send(half));
        require(payable(msg.sender).send(tx.gasprice));
    }

    function addCron(
        address newCron
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CRON_JOB, newCron);
    }

    function safeMint(address to, uint256 tokenId, string memory uri)
        public
        onlyRole(MINTER_ROLE)
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    /*************************
     PRIVATE / INTERNAL
     *************************/

    function _verify(
    NFTVoucher calldata voucher,
    bytes memory signature
    )
    internal
    view
    returns (address) {

    bytes32 digest = _hash(voucher);
    return digest.toEthSignedMessageHash().recover(signature);

  }
    /// @notice Returns a hash of the given NFTVoucher, prepared using EIP712 typed data hashing rules.
    /// @param voucher An NFTVoucher to hash.
    function _hash(NFTVoucher calldata voucher)
    internal
    view
    returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(
      keccak256("NFTVoucher(uint256 tokenId,uint256 minPrice,string uri)"),
      voucher.tokenId,
      voucher.minPrice,
      keccak256(bytes(voucher.uri))
    )));

  }

    /*************************
     OVERRIDES
     *************************/
    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
