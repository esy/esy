// @flow

const { execSync } = require("child_process");

const latestCommit = execSync("git log --oneline -n1").toString("utf8");

if (latestCommit.indexOf("@slowtest") === -1 && !process.env["ESY_SLOWTEST"]) {
    console.log("Not running slowtests.");
    process.exit(0);
}

console.log("-- Running test suite: e2e (slow tests) --");

require("./esy.test.js");
require("./build-top-100-opam.test.js");

// TODO: Unblock these tests
// require("./reason.test.js");
// require("./install-npm.test.js");
