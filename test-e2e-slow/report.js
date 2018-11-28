// @flow

const fs = require('fs');
const os = require('os');
const path = require('path');

// Report JSON format

// JSON format
// { 
//   "win32": { <-- platform
//      "0.4.3": { <-- esy build version
//         "package-name": {
//             success: true/false,
//             validationTime: ...
//         },
//      }
//   }
// }

let writeReport = (packageInfo) => {
    const reportDirectory = path.join(__dirname, "..");

    const esyVersion = JSON.parse(fs.readFileSync(path.join(reportDirectory, "package.json"))).version;

    // Is there an existing report available?
    // If so, we need to merge the results
    const reportFile = path.join(reportDirectory, "opam-support.json");

    let report = {};
    if (fs.existsSync(reportFile)) {
        report = JSON.parse(fs.readFileSync(reportFile));
    }

    let getOrCreate = (obj, key) => {
        if (!obj[key]) {
            obj[key] = {};
        }
        return obj[key];
    };

    let platformNode = getOrCreate(report, os.platform());
    let esyVersionNode = getOrCreate(platformNode, esyVersion);

    let newVersionNode = packageInfo.reduce((acc, curr) => {
        let dup = { ...acc };
        let reportNode = getOrCreate(dup, curr.name);
        reportNode.success = curr.success;
        reportNode.validationTime = curr.validationTime;
        return dup;
    }, esyVersionNode)

    platformNode[esyVersion] = newVersionNode;

    fs.writeFileSync(reportFile, JSON.stringify(report));
};

module.exports = {
    writeReport;
}
