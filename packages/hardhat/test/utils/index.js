const snapshot = require("./snapshot.js");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

module.exports = {
  sleep,
  ...snapshot,
};
