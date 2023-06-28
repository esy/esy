const fs = require('fs');
const path = require('path');
const npmManifest = require(path.join(process.cwd(), 'package.json'));
let releasePostInstallJs = fs
  .readFileSync(path.join(process.cwd(), '.ci/release-postinstall.js'))
  .toString();

let packageName = '@prometheansacrifice/esy-bash';

// Extracting esy-bash version being installed
let matchResults = releasePostInstallJs.match(`npm install ${packageName}@([^\\s]+)`);

if (matchResults !== null && matchResults.length >= 2) {
  let version = matchResults[1];
  if (version !== npmManifest.devDependencies[packageName]) {
    console.log(
      "Version in development manifest, esy.json and release-postinstall.js don't match",
    );
    console.log(`
esy.json - ${npmManifest.devDependencies['${packageName}']}
release-postinstall.js - ${version}
`);
    process.exit(1);
  } else {
    console.log('release-postinstall.js uses the same version as development manifest');
    process.exit(0);
  }
} else {
  console.log(
    'Error: Could not extract esy-bash version being installed in release-postinstall.js',
  );
  process.exit(-1);
}
