// @flow

const fs = require('fs');
const os = require('os');
const path = require('path');

// Report JSON format

// JSON format
// { 
//   "0.4.3": { <-- esy build version
//      "win32": { <-- platform
//         "package-name": {
//             success: true/false,
//             validationTime: ...
//         },
//      }
//   }
// }

let createMarkdownReport = (reportInfo) => {
    let out = Object.keys(reportInfo).map((esyVersion) => {

        let packagesPerPlatform = reportInfo[esyVersion];

        let title = "# " + esyVersion;
        let tableHeaders = "| __Package__ | __OSX__ | __Linux__ | __Windows |";
        let separators = "|-----|-----|-----|-----|";

        let windowsPackages = Object.keys(packagesPerPlatform["win32"]);
        let linuxPackages = Object.keys(packagesPerPlatform["linux"]);
        let osxPackages = Object.keys(packagesPerPlatform["darwin"]);

        let allPackages = [].concat(windowsPackages, linuxPackages, osxPackages);

        let getStatusStringForPlatform = (platform, package) => {
            if (!reportInfo[platform]) {
                return ":question:";
            }

            let packageStatus = reportInfo[platform][package];

            return packageStatus && packageStatus.success ? ":heavy_check_mark:" : ":x";
        };

        let lines = allPackages.map((packageName) => {
            let osxStatus = getStatusStringForPlatform("darwin", packageName);
            let linuxStatus = getStatusStringForPlatform("linux", packageName);
            let winStatus = getStatusStringForPlatform("win32", packageName);

            return `| \`${packageName}\` | ${osxStatus} | ${linuxStatus} | ${winStatus} |`
        })


        return [ title, tableHeaders, separators ].concat(lines).join(os.EOL);
    });

    return out.join(os.EOL + os.EOL);
};

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

    let platformNode = getOrCreate(report, esyVersion);
    let esyVersionNode = getOrCreate(platformNode, os.platform());

    let newVersionNode = packageInfo.reduce((acc, curr) => {
        let dup = { ...acc };
        let reportNode = getOrCreate(dup, curr.name);
        reportNode.success = curr.success;
        reportNode.validationTime = curr.validationTime;
        return dup;
    }, esyVersionNode);

    platformNode[esyVersion] = newVersionNode;

    fs.writeFileSync(reportFile, JSON.stringify(report));
};

module.exports = {
    writeReport;
}
