// @flow

const { execSync } = require("child_process");

const latestCommit = execSync("git -log 1").toString("utf8");

if (latestCommit.indexOf("@slowtest") >= 0) {
    // run slow tests
    console.log("Running test suite: e2e (slow tests)");
    require("./build-top-100-opam.test.js");
    require("./install-npm.test.js");
} else {
    console.log("slowtests: skipping.")
}
