const { getAddress, solidityKeccak256 } = require("ethers/lib/utils");
const keccak256 = require("keccak256");
const { MerkleTree } = require("merkletreejs");

const unique = (a) => {
  const seen = {};
  // eslint-disable-next-line no-return-assign
  return a.filter((item) =>
    // eslint-disable-next-line no-prototype-builtins
    seen.hasOwnProperty(item) ? false : (seen[item] = true)
  );
};

const generateLeaf = (address) =>
  Buffer.from(
    // Hash in appropriate Merkle format
    solidityKeccak256(["address"], [address]).slice(2),
    "hex"
  );

class Snapshot {
  merkleTree;
  snapshot;

  constructor(addresses) {
    this.snapshot = addresses.map((address) => getAddress(address));
    this.snapshot = unique(this.snapshot);

    this.merkleTree = new MerkleTree(
      // Generate leafs
      this.snapshot.map((address) => generateLeaf(address)),
      // Hashing function
      keccak256,
      { sortPairs: true }
    );
  }

  getMerkleRoot() {
    return this.merkleTree.getHexRoot();
  }

  getMerkleProof(address) {
    const leaf = generateLeaf(address);
    return this.merkleTree.getHexProof(leaf);
  }

  verifyAddress(address) {
    const leaf = generateLeaf(address);
    const proof = this.merkleTree.getHexProof(leaf);
    const root = this.getMerkleRoot();
    return this.merkleTree.verify(proof, leaf, root);
  }
}


const getSnapshot = (addresses) => new Snapshot(addresses);

module.exports = { getSnapshot };
