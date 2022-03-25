const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const {
  sleep,
  getSnapshot,
  getDomain,
  types,
  shouldSupportInterfaces,
} = require("./utils");

use(solidity);

const { constants } = ethers;

describe("PoignART", () => {
  let chainId;
  let signers;
  let provider;
  let DEFAULT_ADMIN_ROLE;
  let MINTER_ROLE;
  let CRON_JOB;
  let snapshot;
  let token;

  // quick fix to let gas reporter fetch data from gas station & coinmarketcap
  before(async () => {
    signers = await ethers.getSigners();
    chainId = await signers[0].getChainId();
    provider = signers[0].provider;
    await sleep(2000);

    const PoignART = await ethers.getContractFactory("PoignART");
    token = await PoignART.deploy();
  });

  it("Should deploy PoignART & set default roles", async () => {
    DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
    MINTER_ROLE = await token.MINTER_ROLE();
    CRON_JOB = await token.CRON_JOB();

    expect(
      await token.hasRole(DEFAULT_ADMIN_ROLE, signers[0].address)
    ).to.equal(true);
    expect(await token.hasRole(MINTER_ROLE, signers[0].address)).to.equal(true);
    expect(await token.hasRole(CRON_JOB, signers[0].address)).to.equal(true);
  });

  describe("Merkle Root", () => {
    it("Should update Merkle Root", async () => {
      expect(await token._merkleRoot()).to.equal(constants.HashZero);
      const addresses = signers.slice(0, 3).map((s) => s.address);
      snapshot = getSnapshot(addresses);
      const root = snapshot.getMerkleRoot();
      await token.cronJobRoot(root);
      expect(await token._merkleRoot()).to.equal(root);
    });

    it("Should not update Merkle Root if not CRON_JOB", async () => {
      const root = snapshot.getMerkleRoot();
      const receipt = token.connect(signers[1]).cronJobRoot(root);
      await expect(receipt).to.revertedWith(
        `AccessControl: account ${signers[1].address.toLowerCase()} is missing role ${CRON_JOB}`
      );
    });

    it("Should not update Merkle Root if paused", async () => {
      await token.pause();

      const root = snapshot.getMerkleRoot();
      const receipt = token.cronJobRoot(root);
      await expect(receipt).to.revertedWith("Pausable: paused");

      await token.unpause();
    });

    it("Should verify artist in merkle tree", async () => {
      const addresses = signers.slice(0, 3).map((s) => s.address);
      const proof = snapshot.getMerkleProof(addresses[0]);
      expect(await token.verifyArtist(addresses[0], proof)).to.equal(true);
    });

    it("Should not verify artist not in merkle tree", async () => {
      const addresses = signers.slice(0, 4).map((s) => s.address);
      const snapshot = getSnapshot(addresses);
      const proof = snapshot.getMerkleProof(addresses[3]);
      expect(await token.verifyArtist(addresses[3], proof)).to.equal(false);
    });

    it("Should not add new user to CRON_JOB role if not admin", async () => {
      const receipt = token.connect(signers[1]).addCron(signers[1].address);
      await expect(receipt).to.revertedWith(
        `AccessControl: account ${signers[1].address.toLowerCase()} is missing role ${DEFAULT_ADMIN_ROLE}`
      );
    });

    it("Should add new user to CRON_JOB role & update root", async () => {
      expect(await token.hasRole(CRON_JOB, signers[1].address)).to.equal(false);
      await token.addCron(signers[1].address);
      expect(await token.hasRole(CRON_JOB, signers[1].address)).to.equal(true);

      const addresses = signers.slice(0, 5).map((s) => s.address);
      snapshot = getSnapshot(addresses);
      const root = snapshot.getMerkleRoot();
      await token.connect(signers[1]).cronJobRoot(root);
      expect(await token._merkleRoot()).to.equal(root);
    });
  });

  describe("Redeem", () => {
    it("Should revert tokenURI and ownerOf for non existent token", async () => {
      let receipt = token.tokenURI(1);
      await expect(receipt).to.revertedWith(
        "ERC721URIStorage: URI query for nonexistent token"
      );

      receipt = token.ownerOf(1);
      await expect(receipt).to.revertedWith(
        "ERC721: owner query for nonexistent token"
      );
    });

    it("Should revert redeem when paused", async () => {
      await token.pause();
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = [];

      const receipt = token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Pausable: paused");

      await token.unpause();
    });

    it("Should revert redeem with invalid proof", async () => {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = [];

      const receipt = token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Not authorized!");
    });

    it("Should revert redeem with insufficient funds", async () => {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      const receipt = token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Insufficient funds to redeem");
    });

    it("Should revert redeem with minimum price", async () => {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      const receipt = token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof, { value: 10 });
      await expect(receipt).to.revertedWith(
        "Value must be over the minimum price!"
      );
    });

    it("Should update minimum price", async () => {
      expect(await token.minimumPrice()).to.equal("25000000000000000");
      await token.setMinimum(10);
      expect(await token.minimumPrice()).to.equal(10);
    });

    it("Should redeem a voucher", async () => {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test/1" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      expect(await provider.getBalance(token.address)).to.equal(0);
      expect(await token.balanceOf(signers[1].address)).to.equal(0);

      const receipt = await token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof, { value: 10 });

      await expect(receipt)
        .to.emit(token, "Redeem")
        .withArgs(signers[0].address, signers[1].address, 1, 10);
      await expect(receipt)
        .to.emit(token, "Transfer")
        .withArgs(constants.AddressZero, signers[0].address, 1);
      await expect(receipt)
        .to.emit(token, "Transfer")
        .withArgs(signers[0].address, signers[1].address, 1);

      expect(await provider.getBalance(token.address)).to.equal(10);
      expect(await token.tokenURI(1)).to.equal("ipfs://test/1");
      expect(await token.ownerOf(1)).to.equal(signers[1].address);
      expect(await token.balanceOf(signers[1].address)).to.equal(1);
    });

    it("Should revert for existing tokenId", async () => {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test/1" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      let receipt = token
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof, { value: 10 });

      await expect(receipt).to.revertedWith(`ERC721: token already minted`);
    });

    it("Should redeem another voucher", async () => {
      const voucher = { tokenId: 2, minPrice: 20, uri: "test/2" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, token.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      expect(await provider.getBalance(token.address)).to.equal(10);
      expect(await token.balanceOf(signers[1].address)).to.equal(1);

      const receipt = await token
        .connect(signers[2])
        .redeem(signers[1].address, voucher, signature, proof, { value: 25 });

      await expect(receipt)
        .to.emit(token, "Redeem")
        .withArgs(signers[0].address, signers[1].address, 2, 25);

      expect(await provider.getBalance(token.address)).to.equal(35);
      expect(await token.tokenURI(2)).to.equal("ipfs://test/2");
      expect(await token.ownerOf(2)).to.equal(signers[1].address);
      expect(await token.balanceOf(signers[1].address)).to.equal(2);
    });
  });

  describe("Extended Minting", () => {
    it("Should revert if not MINTER_ROLE", async () => {
      const receipt = token
        .connect(signers[1])
        .extendedMinting(
          signers[1].address,
          signers[0].address,
          10,
          3,
          "test/2"
        );
      await expect(receipt).to.revertedWith(
        `AccessControl: account ${signers[1].address.toLowerCase()} is missing role ${MINTER_ROLE}`
      );
    });

    it("Should revert if insufficient funds", async () => {
      const receipt = token.extendedMinting(
        signers[1].address,
        signers[0].address,
        10,
        3,
        "test/3"
      );
      await expect(receipt).to.revertedWith("Insufficient funds to redeem");
    });

    it("Should revert if token already minted", async () => {
      const receipt = token.extendedMinting(
        signers[1].address,
        signers[0].address,
        10,
        2,
        "test/2",
        { value: 10 }
      );
      await expect(receipt).to.revertedWith("ERC721: token already minted");
    });

    it("Should mint a token", async () => {
      expect(await provider.getBalance(token.address)).to.equal(35);
      expect(await token.balanceOf(signers[1].address)).to.equal(2);

      const receipt = await token.extendedMinting(
        signers[1].address,
        signers[0].address,
        10,
        3,
        "test/3",
        { value: 10 }
      );

      await expect(receipt)
        .to.emit(token, "Redeem")
        .withArgs(signers[0].address, signers[1].address, 3, 10);
      await expect(receipt)
        .to.emit(token, "Transfer")
        .withArgs(constants.AddressZero, signers[0].address, 3);
      await expect(receipt)
        .to.emit(token, "Transfer")
        .withArgs(signers[0].address, signers[1].address, 3);

      expect(await provider.getBalance(token.address)).to.equal(45);
      expect(await token.tokenURI(3)).to.equal("ipfs://test/3");
      expect(await token.ownerOf(3)).to.equal(signers[1].address);
      expect(await token.balanceOf(signers[1].address)).to.equal(3);
    });

    it("Should grant minter role", async () => {
      expect(await token.hasRole(MINTER_ROLE, signers[1].address)).to.equal(
        false
      );
      await token.grantRole(MINTER_ROLE, signers[1].address);
      expect(await token.hasRole(MINTER_ROLE, signers[1].address)).to.equal(
        true
      );
    });

    it("Should mint another token", async () => {
      expect(await provider.getBalance(token.address)).to.equal(45);
      expect(await token.balanceOf(signers[1].address)).to.equal(3);
      expect(await token.balanceOf(signers[2].address)).to.equal(0);

      const receipt = await token
        .connect(signers[1])
        .extendedMinting(
          signers[2].address,
          signers[1].address,
          20,
          4,
          "test/4",
          { value: 25 }
        );

      await expect(receipt)
        .to.emit(token, "Redeem")
        .withArgs(signers[1].address, signers[2].address, 4, 25);

      expect(await provider.getBalance(token.address)).to.equal(70);
      expect(await token.tokenURI(4)).to.equal("ipfs://test/4");
      expect(await token.ownerOf(4)).to.equal(signers[2].address);
      expect(await token.balanceOf(signers[1].address)).to.equal(3);
      expect(await token.balanceOf(signers[2].address)).to.equal(1);
    });
  });

  describe("Withdraw Funds", () => {
    it("Should withdraw all funds", async () => {
      const recipient = await token.UNCHAIN();
      expect(await provider.getBalance(token.address)).to.equal(70);
      const oldBalance = await provider.getBalance(recipient);

      const receipt = await token.withdrawAll();

      await expect(receipt).to.emit(token, "Withdraw").withArgs(recipient, 70);

      expect(await provider.getBalance(recipient)).to.equal(oldBalance.add(70));
    });

    it("Should withdraw all funds again", async () => {
      console.log({ contractWithdraw: this.contractUnderTest?.address });
      const recipient = await token.UNCHAIN();
      expect(await provider.getBalance(token.address)).to.equal(0);
      const oldBalance = await provider.getBalance(recipient);

      await token.extendedMinting(
        signers[2].address,
        signers[1].address,
        50,
        5,
        "test/5",
        { value: 50 }
      );
      expect(await provider.getBalance(token.address)).to.equal(50);
      expect(await token.tokenURI(5)).to.equal("ipfs://test/5");
      expect(await token.ownerOf(5)).to.equal(signers[2].address);
      expect(await token.balanceOf(signers[2].address)).to.equal(2);

      const receipt = await token.withdrawAll();

      await expect(receipt).to.emit(token, "Withdraw").withArgs(recipient, 50);

      expect(await provider.getBalance(recipient)).to.equal(oldBalance.add(50));
    });
  });

  shouldSupportInterfaces([
    "ERC165",
    "ERC721",
    "ERC721Metadata",
    "AccessControl",
  ]);
});
