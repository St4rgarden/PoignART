const snapshot = require("./snapshot.js");
const eip712 = require("./eip712.js");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

module.exports = {
  sleep,
  eip712,
  ...snapshot,
};
