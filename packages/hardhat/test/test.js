const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const { sleep, getSnapshot } = require("./utils");
const { getDomain, types } = require("./utils/eip712");

use(solidity);

const { constants } = ethers;

describe("PoignART", function () {
  let poignart;
  let chainId;
  let signers;
  let provider;
  let DEFAULT_ADMIN_ROLE;
  let MINTER_ROLE;
  let CRON_JOB;
  let snapshot;

  // quick fix to let gas reporter fetch data from gas station & coinmarketcap
  before(async () => {
    signers = await ethers.getSigners();
    chainId = await signers[0].getChainId();
    provider = signers[0].provider;
    await sleep(2000);
  });

  it("Should deploy PoignART & set default roles", async function () {
    const PoignART = await ethers.getContractFactory("PoignART");
    poignart = await PoignART.deploy();

    DEFAULT_ADMIN_ROLE = await poignart.DEFAULT_ADMIN_ROLE();
    MINTER_ROLE = await poignart.MINTER_ROLE();
    CRON_JOB = await poignart.CRON_JOB();

    expect(
      await poignart.hasRole(DEFAULT_ADMIN_ROLE, signers[0].address)
    ).to.equal(true);
    expect(await poignart.hasRole(MINTER_ROLE, signers[0].address)).to.equal(
      true
    );
    expect(await poignart.hasRole(CRON_JOB, signers[0].address)).to.equal(true);
  });

  describe("Merkle Root", function () {
    it("Should update Merkle Root", async function () {
      expect(await poignart._merkleRoot()).to.equal(constants.HashZero);
      const addresses = signers.slice(0, 3).map((s) => s.address);
      snapshot = getSnapshot(addresses);
      const root = snapshot.getMerkleRoot();
      await poignart.cronJobRoot(root);
      expect(await poignart._merkleRoot()).to.equal(root);
    });

    it("Should not update Merkle Root if not CRON_JOB", async function () {
      const root = snapshot.getMerkleRoot();
      const receipt = poignart.connect(signers[1]).cronJobRoot(root);
      await expect(receipt).to.revertedWith(
        `AccessControl: account ${signers[1].address.toLowerCase()} is missing role ${CRON_JOB}`
      );
    });

    it("Should not update Merkle Root if paused", async function () {
      await poignart.pause();

      const root = snapshot.getMerkleRoot();
      const receipt = poignart.cronJobRoot(root);
      await expect(receipt).to.revertedWith("Pausable: paused");

      await poignart.unpause();
    });

    it("Should verify artist in merkle tree", async function () {
      const addresses = signers.slice(0, 3).map((s) => s.address);
      const proof = snapshot.getMerkleProof(addresses[0]);
      expect(await poignart._verifyArtist(addresses[0], proof)).to.equal(true);
    });

    it("Should not verify artist not in merkle tree", async function () {
      const addresses = signers.slice(0, 4).map((s) => s.address);
      const snapshot = getSnapshot(addresses);
      const proof = snapshot.getMerkleProof(addresses[3]);
      expect(await poignart._verifyArtist(addresses[3], proof)).to.equal(false);
    });

    it("Should not add new user to CRON_JOB role if not admin", async function () {
      const receipt = poignart.connect(signers[1]).addCron(signers[1].address);
      await expect(receipt).to.revertedWith(
        `AccessControl: account ${signers[1].address.toLowerCase()} is missing role ${DEFAULT_ADMIN_ROLE}`
      );
    });

    it("Should add new user to CRON_JOB role & update root", async function () {
      expect(await poignart.hasRole(CRON_JOB, signers[1].address)).to.equal(
        false
      );
      await poignart.addCron(signers[1].address);
      expect(await poignart.hasRole(CRON_JOB, signers[1].address)).to.equal(
        true
      );

      const addresses = signers.slice(0, 5).map((s) => s.address);
      snapshot = getSnapshot(addresses);
      const root = snapshot.getMerkleRoot();
      await poignart.connect(signers[1]).cronJobRoot(root);
      expect(await poignart._merkleRoot()).to.equal(root);
    });
  });

  describe("Redeem", function () {
    it("Should revert tokenURI and ownerOf for non existent token", async function () {
      let receipt = poignart.tokenURI(1);
      await expect(receipt).to.revertedWith(
        "ERC721URIStorage: URI query for nonexistent token"
      );

      receipt = poignart.ownerOf(1);
      await expect(receipt).to.revertedWith(
        "ERC721: owner query for nonexistent token"
      );
    });

    it("Should revert redeem when paused", async function () {
      await poignart.pause();
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, poignart.address),
        types,
        voucher
      );
      const proof = [];

      const receipt = poignart
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Pausable: paused");

      await poignart.unpause();
    });

    it("Should revert redeem with invalid proof", async function () {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, poignart.address),
        types,
        voucher
      );
      const proof = [];

      const receipt = poignart
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Not authorized!");
    });

    it("Should revert redeem with insufficient funds", async function () {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, poignart.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      let receipt = poignart
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof);
      await expect(receipt).to.revertedWith("Insufficient funds to redeem");

      receipt = poignart
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof, { value: 5 });
      await expect(receipt).to.revertedWith("Insufficient funds to redeem");
    });

    it("Should redeem a token", async function () {
      const voucher = { tokenId: 1, minPrice: 10, uri: "test" };
      const signature = await signers[0]._signTypedData(
        getDomain(chainId, poignart.address),
        types,
        voucher
      );
      const proof = snapshot.getMerkleProof(signers[0].address);

      expect(await provider.getBalance(poignart.address)).to.equal(0);

      const receipt = await poignart
        .connect(signers[5])
        .redeem(signers[1].address, voucher, signature, proof, { value: 10 });

      await expect(receipt)
        .to.emit(poignart, "Redeem")
        .withArgs(signers[0].address, signers[1].address, 1, 10);

      expect(await provider.getBalance(poignart.address)).to.equal(10);
      expect(await poignart.tokenURI(1)).to.equal("ipfs://test");
      expect(await poignart.ownerOf(1)).to.equal(signers[1].address);
    });
  });
});
