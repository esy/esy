const fs = require('fs');
const path = require('path');

console.log('Creating package.json');
const esyJson = require('../package.json');
const packageJson = JSON.stringify(
  {
    name: esyJson.name,
    version: esyJson.version,
    license: esyJson.license,
    description: esyJson.description,
    repository: esyJson.repository,
    dependencies: {
      '@esy-ocaml/esy-opam': '0.0.15',
      'esy-solve-cudf': esyJson.dependencies['esy-solve-cudf']
    },
    scripts: {
      postinstall: 'node ./postinstall.js'
    },
    bin: {
      esy: '_build/default/esy/bin/esyCommand.exe'
    },
    files: [
      'bin/',
      'postinstall.js',
      'platform-linux/',
      'platform-darwin/',
      'platform-windows-x64/',
      '_build/default/**/*.exe'
    ]
  },
  null,
  2
);

fs.writeFileSync(path.join(__dirname, '..', '_release', 'package.json'), packageJson, {
  encoding: 'utf8'
});

console.log('Copying LICENSE');
fs.copyFileSync(
  path.join(__dirname, '..', 'LICENSE'),
  path.join(__dirname, '..', '_release', 'LICENSE')
);

console.log('Copying README.md');
fs.copyFileSync(
  path.join(__dirname, '..', 'README.md'),
  path.join(__dirname, '..', '_release', 'README.md')
);

console.log('Copying postinstall.js');
fs.copyFileSync(
  path.join(__dirname, 'release-postinstall.js'),
  path.join(__dirname, '..', '_release', 'postinstall.js')
);

console.log('Copying bin/esyInstallRelease.js');
fs.mkdirSync(path.join(__dirname, '..', '_release', 'bin'));
fs.copyFileSync(
  path.join(__dirname, '..', 'bin', 'esyInstallRelease.js'),
  path.join(__dirname, '..', '_release', 'bin', 'esyInstallRelease.js')
);

console.log('Removing artefacts');
fs.rmdirSync(path.join(__dirname, '..', '_release', 'Linux'));
fs.rmdirSync(path.join(__dirname, '..', '_release', 'macOS'));
fs.rmdirSync(path.join(__dirname, '..', '_release', 'Windows'));

console.log('Creating placeholder files');
fs.mkdirSync(path.join(__dirname, '..', '_release', '_build'));
fs.mkdirSync(path.join(__dirname, '..', '_release', '_build', 'default'));
fs.mkdirSync(
  path.join(__dirname, '..', '_release', '_build', 'default', 'esy-build-package')
);
fs.mkdirSync(path.join(__dirname, '..', '_release', '_build', 'default', 'esy'));
fs.mkdirSync(path.join(__dirname, '..', '_release', '_build', 'default', 'esy', 'bin'));
fs.mkdirSync(
  path.join(__dirname, '..', '_release', '_build', 'default', 'esy-build-package', 'bin')
);

const placeholderFile = `#!/usr/bin/env node

console.log("You need to have postinstall enabled")`;

fs.writeFileSync(
  path.join(
    __dirname,
    '..',
    '_release',
    '_build',
    'default',
    'esy',
    'bin',
    'esyCommand.exe'
  ),
  placeholderFile
);
fs.chmodSync(
  path.join(
    __dirname,
    '..',
    '_release',
    '_build',
    'default',
    'esy',
    'bin',
    'esyCommand.exe'
  ),
  0755
);
fs.writeFileSync(
  path.join(
    __dirname,
    '..',
    '_release',
    '_build',
    'default',
    'esy-build-package',
    'bin',
    'esyBuildPackageCommand.exe'
  ),
  placeholderFile
);
fs.chmodSync(
  path.join(
    __dirname,
    '..',
    '_release',
    '_build',
    'default',
    'esy-build-package',
    'bin',
    'esyBuildPackageCommand.exe'
  ),
  0755
);
