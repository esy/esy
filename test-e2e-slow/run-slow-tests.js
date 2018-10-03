// @flow

const { execSync } = require("child_process");

const latestCommit = execSync("git log --oneline -n1").toString("utf8");

// run slow tests
// NOMERGE: Always run slow tests in this branch
console.log("Running test suite: e2e (slow tests)");

require("./build-top-100-opam.test.js");
require("./install-npm.test.js");
require("./esy.test.js");
require("./reason.test.js");
