// SPDX-License-Identifier: MIT
// @author Kyle_Stargarden w/ Big thanks to yusefnapora and NFTCulture
pragma solidity ^0.8.4;
pragma abicoder v2;

import "./Parents/ERC721Public.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PoignART is ERC721, EIP712, ERC721URIStorage, Pausable, AccessControl {

    using ECDSA for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CRON_JOB = keccak256("CRON_JOB");
    bytes32 public constant VETTER_ROLE = keccak256("VETTER_ROLE");
    uint public constant MINIMUMPRICE = 0.025 ether;
    address public constant UNCHAIN = 0x10E1439455BD2624878b243819E31CfEE9eb721C;
    address public constant GITCOIN = 0xde21F729137C5Af1b01d73aF1dC21eFfa2B8a0d6;
    address public constant TEST = 0x66F59a4181f43b96fE929b711476be15C96B83B3;
    // address public constant UKRAINEDAO = 0x633b7218644b83D57d90e7299039ebAb19698e9C;

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

    // voucher object is signed and stored off-chain to enable and enforce dutch auction with lazy minting
    struct AuctionNFTVoucher {

        // @notice The id of the token to be redeemed
        uint256 tokenId;
        // @notice The maximum starting price of the Dutch Auction
        uint256 maxPrice;
        // @notice The minimum final price of the Dutch Auction
        uint256 minPrice;
        // @notice The metadata URI to associate with this token
        string uri;
        // @notice The starting time of the Dutch Auction
        uint256 startTime;
        // @notice The ending time of the Dutch Auction
        uint256 endTime;

    }

    // event for withdrawal to both Gitcoin Unchain and Giveth Unchain
    event WithdrawSplit(uint indexed gitcoinUnchain, uint indexed givethUnchain);

    // event for withdrawal after GR13
    event Withdraw(uint indexed givethUnchain);

    // event allows indexing of artists who have gained MINTER_ROLE and for which _merkleRoot version
    event Vetted (
        // @notice The address of the vetted artist
        address artist,
        // @notice The merkleRoot that they used for authentication
        bytes32 _merkleRoot
    );


    constructor() ERC721("PoignART", "[+++||=====>") EIP712("PoignardVoucher", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(CRON_JOB, msg.sender);
        _grantRole(VETTER_ROLE, msg.sender);
        _setRoleAdmin(MINTER_ROLE, VETTER_ROLE);
    }

    /*************************
     STATE VARIABLES
     *************************/

    // the _merkleRoot allowing authentication of all users from snapshot and community vetting
    bytes32 public _merkleRoot;
    // records the time stamp at time of update - used to enforce 43200 seconds between updates by CRON_JOB
    uint _lastUpdate;

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
    function _verify(

        address _artist,

        bytes32[] calldata _merkleProof
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

    // current price of Dutch Auction
    function getAuctionPrice(AuctionNFTVoucher calldata voucher)
        public view returns (uint256) {

        // calculate total possible price reduction
        uint256 maxPriceReduction = voucher.maxPrice - voucher.minPrice;

        // total time of the auction in seconds
        uint256 totalAuctionLength = voucher.endTime - voucher.startTime;

        // price reduction per second
        uint256 reductionMultiplier = maxPriceReduction / totalAuctionLength;

        // number of seconds since the auction started
        uint256 auctionSeconds = block.timestamp - voucher.startTime;

        // the total price reduction at the current timestamp
        uint256 priceReduction = reductionMultiplier * auctionSeconds;

        // price at the current timestamp
        uint256 currentPrice = voucher.maxPrice - priceReduction;

        return currentPrice;

    }

    /*************************
     USER FUNCTIONS
     *************************/

    // function authenticates artists through the merkle tree and assigns MINTER_ROLE
    function vetArtist(

        address artist,

        bytes32[] calldata _merkleProof
    )
        public
        whenNotPaused {

        require(_msgSender() == artist, "Artists have to add themselves!");
        require(_verify(artist, _merkleProof), "Not authorized!");
        _grantRole(MINTER_ROLE, artist);
        emit Vetted(artist, _merkleRoot);

    }


    // function allows collectors to purchase and mint NFTs of artist's with MINTER_ROLE
    function redeemByRole(
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

    // make sure that the signer is authorized to mint NFTs via MINTER_ROLE
    require(hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized!");

    // require the current price is above 0.025 ETH
    require(voucher.minPrice > MINIMUMPRICE, "Price must be greater than 0.025 eth!");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= voucher.minPrice, "Insufficient funds to redeem!");

    // mint token to collector and set it's IPFS URI
    _mint(redeemer, voucher.tokenId);
    _setTokenURI(voucher.tokenId, voucher.uri);

    return voucher.tokenId;
  }


    // function allows collectors to purchase and mint NFTs of artist's who belong to the merkle tree
    function redeemByMerkle(
        address redeemer,
        NFTVoucher calldata voucher,
        bytes memory signature,
        bytes32[] calldata _merkleProof
    )
        public
        payable
        callerIsUser
        whenNotPaused
        returns (uint256) {

    // make sure signature is valid and get the address of the signer
    address signer = _verify(voucher, signature);

    // make sure that the signer is authorized to mint NFTs via merkle tree
    require(_verify(signer, _merkleProof), "Not authorized!");

    // require the current price is above 0.025 ETH
    require(voucher.minPrice > MINIMUMPRICE, "Price must be greater than 0.025 eth!");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= voucher.minPrice, "Insufficient funds to redeem");

    // mint token to collector and set it's IPFS URI
    _mint(redeemer, voucher.tokenId);
    _setTokenURI(voucher.tokenId, voucher.uri);

    return voucher.tokenId;
  }


    // allows collectors to purchase and mint auctioned NFTs of artist's with MINTER_ROLE through
    function redeemAuctionRole(
        address redeemer,
        AuctionNFTVoucher calldata voucher,
        bytes memory signature
    )
        public
        payable
        callerIsUser
        whenNotPaused
        returns (uint256) {

    // require that the auction has not ended
    require(block.timestamp < voucher.endTime, "Auction has finished!");

    // require that the auction has started
    require(block.timestamp > voucher.startTime, "Auction hasn't started!");

    // make sure signature is valid and get the address of the signer
    address signer = _verifyAuction(voucher, signature);

    // make sure that the signer is authorized to mint NFTs via MINTER_ROLE
    require(hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized");

    // calculate the current price for this Dutch Auction
    uint currentPrice = getAuctionPrice(voucher);

    // require the current price is above 0.025 ETH
    require(currentPrice > MINIMUMPRICE, "Price must be greater than 0.025 eth!");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= currentPrice, "Insufficient funds to redeem");

    // mint token to collector and set it's IPFS URI
    _mint(redeemer, voucher.tokenId);
    _setTokenURI(voucher.tokenId, voucher.uri);

    return voucher.tokenId;
  }

    // allows collectors to purchase and mint auctioned NFTs of artist's who belong to merkle tree
    function redeemAuctionMerkle(
        address redeemer,
        AuctionNFTVoucher calldata voucher,
        bytes memory signature,
        bytes32[] calldata _merkleProof
    )
        public
        payable
        callerIsUser
        whenNotPaused
        returns (uint256) {

    // require that the auction has not ended
    require(block.timestamp < voucher.endTime, "Auction has finished!");

    // require that the auction has started
    require(block.timestamp > voucher.startTime, "Auction hasn't started!");

    // make sure signature is valid and get the address of the signer
    address signer = _verifyAuction(voucher, signature);

    // make sure that the signer is authorized to mint NFTs via merkle tree
    require(_verify(signer, _merkleProof), "Not authorized!");

    // calculate the current price for Dutch AuctionNFTVoucher
    uint currentPrice = getAuctionPrice(voucher);

    // require the current price is above 0.025 ETH
    require(currentPrice > MINIMUMPRICE, "Price must be greater than 0.025 eth!");

    // make sure that the redeemer is paying enough to cover the buyer's cost
    require(msg.value >= currentPrice, "Insufficient funds to redeem");

    // mint token to collector and set it's IPFS URI
    _mint(redeemer, voucher.tokenId);
    _setTokenURI(voucher.tokenId, voucher.uri);

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

    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    // function for adding new updated roots for vetting process
    function cronJobRoot(
        bytes32 newRoot
    )
        external onlyRole(CRON_JOB) whenNotPaused {
        _merkleRoot = newRoot;
    }

    /** @dev Function for withdrawing ETH to Unchain via Giveth and Gitcoin
    * Constants are used for transparency and safety
    */
    function withdrawAllSplit()
        public
    {
        require(block.timestamp < 1648083600, "GR 13 is closed!  Use withdrawAll");
        uint half = address(this).balance / 2;
        emit WithdrawSplit(half, half);
        require(payable(UNCHAIN).send(half));
        require(payable(GITCOIN).send(half));
    }

    /** @dev Function for withdrawing ETH to our test address
    * Constants are used for transparency and safety
    */
    function withdrawAll()
        public
    {
        require(block.timestamp > 1648083600, "GR 13 is still open! Use withdrawAllSplit");
        emit Withdraw(address(this).balance);
        require(payable(UNCHAIN).send(address(this).balance));
    }

    /** @dev Function for withdrawing ETH to our test address
    * Constants are used for transparency and safety
    */
    function testWithdrawAll()
        public
        onlyRole(CRON_JOB)
    {
        require(payable(TEST).send(address(this).balance));
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

    function _verifyAuction(
    AuctionNFTVoucher calldata voucher,
    bytes memory signature
    )
    internal
    view
    returns (address) {

    bytes32 digest = _hashAuction(voucher);
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

    /// @notice Returns a hash of the given NFTVoucher, prepared using EIP712 typed data hashing rules.
    /// @param voucher An NFTVoucher to hash.
    function _hashAuction(AuctionNFTVoucher calldata voucher)
    internal
    view
    returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(
      keccak256("AuctionNFTVoucher(uint256 tokenId,uint256 maxPrice,uint256 minPrice,string uri,uint256 startTime,uint256 endTime)"),
      voucher.tokenId,
      voucher.maxPrice,
      voucher.minPrice,
      keccak256(bytes(voucher.uri)),
      voucher.startTime,
      voucher.endTime
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
