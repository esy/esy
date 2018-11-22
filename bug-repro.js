// @flow

const {execSync, spawnSync} = require('child_process');

// console.log(execSync('echo $PATH').toString('utf8'));
let p = process.env.PATH;
console.log("PATH: " + JSON.stringify(process.env.Path));

// Rule out this being an issue
p = p.split("\\").join("/");

let clipFirstPath = (p) => p.substring(p.indexOf(";") + 1, p.length);

let passed = false;
do {
    p = clipFirstPath(p)
    console.log("p is now length: " + p.length);
    try {
        execSync('git log -n1', {env: { Path: p}}).toString('utf8');
        console.log("Git call succeeded!");
        passed = true;
    } catch(ex) { }

} while (!passed)
