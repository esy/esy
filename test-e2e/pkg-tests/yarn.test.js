/* @flow */

const path = require('path');
const {
  tests: {generatePkgDriver, startPackageServer, getPackageRegistry, clearPackageRegistry},
  exec: {execFile},
} = require(`pkg-tests-core`);

const {
  basic: basicSpecs,
  dragon: dragonSpecs,
  script: scriptSpecs,
} = require(`pkg-tests-specs`);

const devDependenciesSpecs = require('pkg-tests-specs/sources/devDependencies.js');

const cwd = process.cwd();
const esyiCommand = path.join(
  cwd,
  '..',
  '..',
  '_build',
  'install',
  'default',
  'bin',
  'esyi',
);

const esyiCommands = new Set([
  'install',
  'print-cudf-universe',
]);

const pkgDriver = generatePkgDriver({
  runDriver: (path, line, {registryUrl}) => {
    if (line.length === 1 && esyiCommands.has(line[0])) {
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
      return execFile(esyiCommand, [...extraArgs], {cwd: path});
    } else {
      const prg = line[0];
      const args = line.slice(1);
      return execFile(prg, [...args], {cwd: path});
    }
  },
});

beforeEach(async () => {
  await clearPackageRegistry();
  await startPackageServer();
  await getPackageRegistry();
});

basicSpecs(pkgDriver);
devDependenciesSpecs(pkgDriver);
//dragonSpecs(pkgDriver);
//scriptSpecs(pkgDriver);
