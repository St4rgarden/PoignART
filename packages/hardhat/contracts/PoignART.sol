// SPDX-License-Identifier: MIT
// @author Kyle_Stargarden w/ Big thanks to yusefnapora and NFTCulture
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PoignART is ERC721, EIP712, ERC721URIStorage, Pausable, AccessControl {

    using ECDSA for bytes32;

    // #todo change the GIVETH AND GITCOIN addresses to be correct
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CRON_JOB = keccak256("CRON_JOB");
    address public constant CRON = 0x66F59a4181f43b96fE929b711476be15C96B83B3;
    // address public constant GIVETH = 0x10E1439455BD2624878b243819E31CfEE9eb721C;
    // address public constant GITCOIN = 0xde21F729137C5Af1b01d73aF1dC21eFfa2B8a0d6;

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

    uint minimumPrice;

    // event for indexing withdrawals
    event Withdraw(address indexed recipient, uint value);
    // event for indexing redeems
    event Redeem(address indexed signer, address indexed redeemer, uint tokenId, uint value);

    constructor() ERC721("PoignART", "[+++||=====>") EIP712("PoignartVoucher", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(CRON_JOB, msg.sender);
        minimumPrice = 0.025 ether;
    }

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
        return "ipfs://";
    }

    /*************************
     USER FUNCTIONS
     *************************/

    function redeem(
        address redeemer,
        NFTVoucher calldata voucher,
        bytes calldata signature,
        bytes32[] calldata merkleProof
    )
        public
        payable
        callerIsUser
        whenNotPaused
        returns (uint256) {

    // make sure signature is valid and get the address of the signer
    address signer = _verify(voucher, signature);

    // make sure that the signer is authorized to mint NFTs
    require(_verifyArtist(signer, merkleProof), "Not authorized!");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= voucher.minPrice, "Insufficient funds to redeem");
    require(msg.value >= minimumPrice, "Value must be over the minimum price!");

    // first assign the token to the signer, to establish provenance on-chain
    _mint(signer, voucher.tokenId);

    // assign the token URI to it's correct ipfs address
    _setTokenURI(voucher.tokenId, voucher.uri);

    // transfer the token to the redeemer
    _transfer(signer, redeemer, voucher.tokenId);

    emit Redeem(signer, redeemer, voucher.tokenId, msg.value);

    return voucher.tokenId;
  }


    /*************************
     ACCESS CONTROL FUNCTIONS
     *************************/

    // allows cron role to change the minimum price
    function setMinimum(
            uint newMinimum
    )
        external
        onlyRole(CRON_JOB) {
        minimumPrice = newMinimum;
    }

     // allows extended functionality for Dutch Auction etc
    function extendedMinting(
        address redeemer,
        address signer,
        uint price,
        uint tokenId,
        string calldata uri
    )
        external
        payable
        onlyRole(MINTER_ROLE)
        returns (uint256) {

        //enforce the minimum price
        require(msg.value >= price, "Insufficient funds to redeem");
        require(msg.value >= minimumPrice, "Value must be over the minimum price!");

        // first assign the token to the signer, to establish provenance on-chain
        _mint(signer, tokenId);

        // assign the token URI to it's correct ipfs address
        _setTokenURI(tokenId, uri);

        // transfer the token to the redeemer
        _transfer(signer, redeemer, tokenId);

        // index creator, collector and payment data for subgraph
        emit Redeem(signer, redeemer, tokenId, msg.value);

        return tokenId;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // function for adding new updated roots for vetting process
    function cronJobRoot(
        bytes32 newRoot
    )
        external onlyRole(CRON_JOB) whenNotPaused {
        _merkleRoot = newRoot;
    }

    /** @dev Function for withdrawing ETH to Unchain via Giveth
    * Constants are used for transparency and safety
    */
    function withdrawAll()
        public
    {
        emit Withdraw(CRON, address(this).balance);
        require(payable(CRON).send(address(this).balance));
    }

    function addCron(
        address newCron
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CRON_JOB, newCron);
    }

    /*************************
     PRIVATE / INTERNAL
     *************************/

    /// @notice recovers the address of the original voucher signer from NFTVoucher
    /// @param voucher that contains necessary data for redeeming an NFT
    /// @param signature generated from private key and original NFTVoucher object
    function _verify(
    NFTVoucher calldata voucher,
    bytes memory signature
    )
    internal
    view
    returns (address) {

    bytes32 digest = _hash(voucher);
    return digest.recover(signature);

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
