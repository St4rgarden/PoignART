const snapshot = require("./snapshot.js");
const eip712 = require("./eip712.js");
const erc165 = require("./erc165.js");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

module.exports = {
  sleep,
  ...eip712,
  ...erc165,
  ...snapshot,
};
