const { expect, use } = require("chai");
const { solidity } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const { sleep, getSnapshot } = require("./utils");

use(solidity);

const { constants } = ethers;

describe("PoignART", function () {
  let poignart;
  let signers;
  let DEFAULT_ADMIN_ROLE;
  let MINTER_ROLE;
  let CRON_JOB;
  let snapshot;

  // quick fix to let gas reporter fetch data from gas station & coinmarketcap
  before(async () => {
    signers = await ethers.getSigners();
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
});
