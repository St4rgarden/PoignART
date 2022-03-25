const { makeInterfaceId } = require("@openzeppelin/test-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const INTERFACES = {
  ERC165: ["supportsInterface(bytes4)"],
  ERC721: [
    "balanceOf(address)",
    "ownerOf(uint256)",
    "approve(address,uint256)",
    "getApproved(uint256)",
    "setApprovalForAll(address,bool)",
    "isApprovedForAll(address,address)",
    "transferFrom(address,address,uint256)",
    "safeTransferFrom(address,address,uint256)",
    "safeTransferFrom(address,address,uint256,bytes)",
  ],
  ERC721Metadata: ["name()", "symbol()", "tokenURI(uint256)"],
  AccessControl: [
    "hasRole(bytes32,address)",
    "getRoleAdmin(bytes32)",
    "grantRole(bytes32,address)",
    "revokeRole(bytes32,address)",
    "renounceRole(bytes32,address)",
  ],
};

const INTERFACE_IDS = {};
const FN_SIGNATURES = {};
for (const k of Object.getOwnPropertyNames(INTERFACES)) {
  INTERFACE_IDS[k] = makeInterfaceId.ERC165(INTERFACES[k]);
  for (const fnName of INTERFACES[k]) {
    // the interface id of a single function is equivalent to its function signature
    FN_SIGNATURES[fnName] = makeInterfaceId.ERC165([fnName]);
  }
}

const shouldSupportInterfaces = (interfaces = []) => {
  describe("ERC165", () => {
    before(async () => {
      const PoignART = await ethers.getContractFactory("PoignART");
      this.contractUnderTest = await PoignART.deploy();
    });

    it("supportsInterface uses less than 30k gas", async () => {
      for (const k of interfaces) {
        const interfaceId = INTERFACE_IDS[k];
        expect(
          await this.contractUnderTest.estimateGas.supportsInterface(
            interfaceId
          )
        ).to.be.lte(30000);
      }
    });

    it("all interfaces are reported as supported", async () => {
      for (const k of interfaces) {
        const interfaceId = INTERFACE_IDS[k];
        expect(
          await this.contractUnderTest.supportsInterface(interfaceId)
        ).to.equal(true);
      }
    });

    it("all interface functions are in ABI", async () => {
      const contractFns = Object.keys(
        this.contractUnderTest.interface.functions
      );

      for (const k of interfaces) {
        for (const fnName of INTERFACES[k]) {
          expect(contractFns).to.include(fnName);
        }
      }
    });
  });
};

module.exports = {
  shouldSupportInterfaces,
};
