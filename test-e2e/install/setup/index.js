/* @flow */

const path = require('path');
const exec = require('./exec');
const fs = require('./fs');
const tests = require('./tests');

const cwd = process.cwd();
const esyiCommand = path.join(
  __dirname,
  '..',
  '..',
  '..',
  '_release',
  '_build',
  'default',
  'esy',
  'bin',
  'esyCommand.exe'
);

const InstallCommand = process.platform === "win32" ? "legacy-install" : "install";

const legacyCommands = new Set(['legacy-install'])
const esyiCommands = new Set(['install', 'print-cudf-universe']);

const makeTemporaryEnv = tests.generatePkgDriver({
  runDriver: (path, line, {registryUrl}) => {
    if (line.length === 1 && legacyCommands.has(line[0])) {
      const extraArgs = [
        `legacy-install`,
        `--cache-path`,
        `${path}/.cache`,
        `--npm-registry`,
        registryUrl,
        `--opam-repository`,
        `${cwd}/opam-repository`,
        `--opam-override-repository`,
        `${cwd}/esy-opam-override`,
      ];
      return exec.execFile(esyiCommand, [...extraArgs], {cwd: path});
    } else if (line.length === 1 && esyiCommands.has(line[0])) {
      const extraArgs = [
        `--cache-path`,
        `${path}/.cache`,
        `--npm-registry`,
        registryUrl,
        `--opam-repository`,
        `:${cwd}/opam-repository`,
        `--opam-override-repository`,
        `:${cwd}/esy-opam-override`,
      ];
      return exec.execFile(esyiCommand, [...extraArgs], {cwd: path});
    } else {
      const prg = line[0];
      const args = line.slice(1);
      return exec.execFile(prg, [...args], {cwd: path});
    }
  },
});

jest.setTimeout(30000);

beforeEach(async function commonBeforeEach() {
  await tests.clearPackageRegistry();
  await tests.startPackageServer();
  await tests.getPackageRegistry();
});

module.exports = {
  getPackageDirectoryPath: tests.getPackageDirectoryPath,
  getPackageHttpArchivePath: tests.getPackageHttpArchivePath,
  getPackageArchivePath: tests.getPackageArchivePath,
  definePackage: tests.definePackage,
  defineLocalPackage: tests.defineLocalPackage,
  makeTemporaryEnv: makeTemporaryEnv,
  crawlLayout: tests.crawlLayout,
  makeFakeBinary: fs.makeFakeBinary,
  exists: fs.exists,
  readdir: fs.readdir,
  execFile: exec.execFile,
  InstallCommand,
};
