// @flow

const {execSync} = require('child_process');
const path = require('path');
const fs = require('fs-extra');
const semver = require('semver');
const {name, version} = require('../package.json');

function exec(cmd) {
  console.log(`exec: ${cmd}`);
  return execSync(cmd).toString();
}

function error(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

const args = process.argv.slice(2);

const commit = args[0] != null ? args[0] : exec(`git rev-parse --verify HEAD`);
const nightyVersion = `${version}-${commit.slice(0, 6)}`;

const tarballUrl = `https://registry.npmjs.org/@esy-nightly/esy/-/esy-${nightyVersion}.tgz`

const root = path.resolve(path.join(__dirname, '..', '_release'));
const tarball = path.join(root, 'package.tgz');
const pkgJson = path.join(root, 'package', 'package.json');

fs.removeSync(root);
fs.mkdirSync(root);

exec(`curl --location "${tarballUrl}" --output "${tarball}"`);
exec(`tar xzf "${tarball}" -C "${root}"`);

const pkgJsonData = JSON.parse(fs.readFileSync(pkgJson, 'utf8'));
pkgJsonData.name = name;
pkgJsonData.version = version;
fs.writeFileSync(pkgJson, JSON.stringify(pkgJsonData, null, 2));

console.log(`
  *********************************************************

  Release ${name}@${version} is ready at "_release/package"

  - It is the same code as @esy-nightly/esy@${nightyVersion}.

  - Make sure you review _release/package/package.json,
    it has "name" and "version" fields updated to "${name}" and "${version}".

  - You can manually install it:

    % cd _release/package
    % npm pack
    % npm install -g ./${name}-${version}.tgz

  - If you are ready, publish it:

    % cd _release/package
    % npm publish --otp=<OTP-CODE> --tag <latest|next>

  Happy hacking!

  *********************************************************
`);
