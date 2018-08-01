/**
 * Utilities for mocking opam registry.
 *
 * @flow
 */

const path = require('path');
const fs = require('fs-extra');
const {createTemporaryFolder} = require('./fs.js');

export opaque type OpamRegistry = {
  registryPath: string,
  overridePath: string,
};

async function initialize(): Promise<OpamRegistry> {
  const registryPath = await createTemporaryFolder();
  const overridePath = await createTemporaryFolder();
  return {registryPath, overridePath};
}

async function defineOpamPackage(
  registry: OpamRegistry,
  spec: {
    name: string,
    version: string,
    opam: string,
    url: ?string,
  },
) {
  const packagePath = path.join(registry.registryPath, spec.name);
  await fs.mkdirp(packagePath);

  const packageVersionPath = path.join(packagePath, `${spec.name}.${spec.version}`);
  await fs.mkdirp(packageVersionPath);

  await fs.writeFile(path.join(packageVersionPath, 'opam'), spec.opam);
  if (spec.url != null) {
    await fs.writeFile(path.join(packageVersionPath, 'url'), spec.opam);
  }
}
