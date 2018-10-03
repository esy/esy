// @flow

const { execSync } = require("child_process");

const latestCommit = execSync("git log --oneline -n1").toString("utf8");

// run slow tests
// NOMERGE: Always run slow tests in this branch
console.log("Running test suite: e2e (slow tests)");

// INVESTIGATE
// require("./install-npm.test.js");

// Blocked by esy installer issue...
// require("./reason.test.js");

require("./esy.test.js");

require("./build-top-100-opam.test.js");

