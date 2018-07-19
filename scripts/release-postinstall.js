/**
 * release-postinstall.js
 *
 * This script is bundled with the `npm` package and executed on release.
 * Since we have a 'fat' NPM package (with all platform binaries bundled),
 * this postinstall script extracts them and puts the current platform's
 * bits in the right place.
 */


var path = require('path');
var cp = require('child_process');
var fs = require('fs');
var os = require('os');
var platform = process.platform;

const copyPlatformBinaries = (platformPath) => {
    fs.renameSync(
        path.join(__dirname, 'platform-' + platformPath, '_build'),
        path.join(__dirname, '_build')
    );
    fs.renameSync(
        path.join(__dirname, 'platform-' + platformPath, 'bin', 'fastreplacestring'),
        path.join(__dirname, 'bin', 'fastreplacestring')
    );

    fs.unlinkSync(path.join(__dirname, 'bin', 'esy'));
    fs.symlinkSync(
        path.join(__dirname, '_build', 'default', 'esy', 'bin', 'esyCommand.exe'),
        path.join(__dirname, 'bin', 'esy')
    );

    fs.unlinkSync(path.join(__dirname, 'bin', 'esyi'));
    fs.symlinkSync(
        path.join(__dirname, '_build', 'default', 'esyi', 'bin', 'esyi.exe'),
        path.join(__dirname, 'bin', 'esyi')
    );
}

switch (platform) {
    case 'win32':
        if (os.arch() !== "x64") {
            console.warn("error: x86 is currently not supported on Windows");
            process.exit(1);
        }

        copyPlatformBinaries("windows-x64");

        console.log("Installing cygwin sandbox...");
        cp.execSync("npm install esy-bash");
        console.log("Cygwin installed successfully.");
        break;
    case 'linux':
    case 'darwin':
        copyPlatformBinaries(platform);
        break;
    default:
        console.warn("error: no release built for the " + platform + " platform");
        process.exit(1);
}
