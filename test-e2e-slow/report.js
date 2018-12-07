// @flow

const fs = require('fs');
const os = require('os');
const path = require('path');

// Report JSON format

// JSON format
// { 
//   "0.4.3": { <-- esy build version
//         "package-name": {
//             success: true/false,
//             validationTime: ...
//         },
//      }
// }

let createMarkdownReport = (reportInfo) => {
    let out = Object.keys(reportInfo).map((esyVersion) => {
        let packages = reportInfo[esyVersion];

        let title = "# " + esyVersion;
        let tableHeaders = "| __Package__ | | __Windows Compatibility__ |";
        let separators = "|-----|-----|";

        let getStatusString = (package) => {
            let packageStatus = packages[package];

            return packageStatus && packageStatus.success ? ":heavy_check_mark:" : ":x";
        };

        let lines = Object.keys(packages).map((packageName) => {
            let winStatus = getStatusString(packageName);

            return `| \`${packageName}\` | ${winStatus} |`
        })


        return [ title, tableHeaders, separators ].concat(lines).join(os.EOL);
    });

    return out.join(os.EOL + os.EOL);
};

let writeReport = (packageInfo) => {
    const rootDirectory = path.join(__dirname, "..");
    const reportDirectory = path.join(rootDirectory, "_report");

    if (!fs.existsSync(reportDirectory)) {
        fs.mkdirSync(reportDirectory);
    }

    const esyVersion = JSON.parse(fs.readFileSync(path.join(rootDirectory, "package.json"))).version;

    // Is there an existing report available?
    // If so, we need to merge the results
    // TODO: Set this up to the artifact path correctly
    const reportJsonFile = path.join(reportDirectory, "windows-opam-support.json");
    const reportMarkdownFile = path.join(reportDirectory, "windows-opam-support.md");

    let report = {};
    if (fs.existsSync(reportJsonFile)) {
        report = JSON.parse(fs.readFileSync(reportJsonFile));
    }

    let getOrCreate = (obj, key) => {
        if (!obj[key]) {
            obj[key] = {};
        }
        return obj[key];
    };

    let esyVersionNode = getOrCreate(report, esyVersion);

    let newVersionNode = packageInfo.reduce((acc, curr) => {
        let dup = { ...acc };
        let reportNode = getOrCreate(dup, curr.name);
        reportNode.success = curr.success;
        reportNode.validationTime = curr.validationTime;
        return dup;
    }, esyVersionNode);

    report[esyVersion] = newVersionNode;

    fs.writeFileSync(reportJsonFile, JSON.stringify(report));

    let markdownVersion = createMarkdownReport(report);
    fs.writeFileSync(reportMarkdownFile, markdownVersion);
};

module.exports = {
    writeReport
};
