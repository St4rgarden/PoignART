const getDomain = (chainId, verifyingContract) => ({
  name: "PoignartVoucher",
  version: "1",
  verifyingContract,
  chainId,
});

const types = {
  NFTVoucher: [
    { name: "tokenId", type: "uint256" },
    { name: "minPrice", type: "uint256" },
    { name: "uri", type: "string" },
  ],
};

module.exports = {
    getDomain,
    types,
}
