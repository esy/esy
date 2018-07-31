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

const binariesToCopy = [
    path.join('_build', 'default', 'esyi', 'bin', 'esyi.exe'),
    path.join('_build', 'default', 'esy', 'bin', 'esyCommand.exe'),
    path.join('_build', 'default', 'esy-build-package', 'bin', 'esyBuildPackageCommand.exe'),
    path.join('bin', 'fastreplacestring'),
]

const copyPlatformBinaries = (platformPath) => {
    const platformBuildPath = path.join(__dirname, 'platform-' + platformPath);

    binariesToCopy.forEach(binaryPath => {
        const sourcePath = path.join(platformBuildPath, binaryPath);
        const destPath = path.join(__dirname, binaryPath);
        console.log(`- Copying file ${sourcePath} to {destPath}.`);
        if (fs.existsSync(destPath)) {
            fs.unlinkSync(destPath);
        }
        fs.copyFileSync(sourcePath, destPath);
    });
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
