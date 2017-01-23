/**
 * @flow
 */

import type {Sandbox} from '../Sandbox';

import {tmpdir} from 'os';
import path from 'path';
import fs from 'mz/fs';
import execa from 'execa';
import semver from 'semver';
import tempfile from 'tempfile';
import chalk from 'chalk';
import ndjson from 'ndjson';
import bole from 'bole';

import * as pnpm from '@esy-ocaml/pnpm';
import mkdirp from '@esy-ocaml/pnpm/lib/fs/mkdirp';
import {fetchFromTarball} from '@esy-ocaml/pnpm/lib/install/fetchResolution';
import {hash} from '../Utility';
import initLogger from './logger';

export type PackageJsonCollection = {
  versions: {
    [name: string]: PackageJson;
  }
};

export type PackageJson = {
  name: string;
  version: string;
  opam: {
    url: string;
    patch?: string;
  }
};

export type OpamInfo = {
  opam: {
    name: string;
    version: string;
  }
};

const OPAM_METADATA_STORE = path.join(__dirname, '..', '..', 'opam-packages');

const USER_HOME: string = (process.env.HOME: any)

const STORE_PATH = (
  process.env.ESY__STORE ||
  path.join(USER_HOME, '.esy', '_fetch')
);

const installationSpec = {

  storePath: STORE_PATH,
  preserveSymlinks: false,
  lifecycle: {

    packageWillResolve: async (spec, opts) => {
      switch (spec.type) {
        case 'range':
        case 'version':
        case 'tag': {
          if (spec.scope === '@opam') {
            return resolveFromOpam(spec, opts);
          }
        }
      }
      // fallback to pnpm's resolution algo
      return null;
    },

    packageWillFetch: async (target, resolution, opts) => {
      if (resolution.opam == null) {
        // fallback to pnpm's fetching algo
        return false;
      } else {
        await fetchFromTarball(target, {tarball: resolution.tarball}, opts);
        return true;
      }
    },

    packageDidFetch: async (target, resolution) => {
      const packageJsonFilename = path.join(target, 'package.json')

      if (resolution.opam == null) {
        let packageJson: PackageJson = await readJson(packageJsonFilename);
        packageJson = {...packageJson, _resolved: resolution.id};
        await writeJson(packageJsonFilename, packageJson);

      } else {
        const {name, version} = resolution.opam;
        const packageCollection = await lookupPackageCollection(name);

        let packageJson = packageCollection.versions[version];
        packageJson = {...packageJson, _resolved: resolution.id};
        writeJson(packageJsonFilename, packageJson);

        await applyPatch(packageJson, target);
      }
    },
  }
}

async function applyPatch(packageJson: PackageJson, target: string) {
  if (packageJson.opam.patch) {
    const patchFilename = path.join(target, '_esy_patch');
    await fs.writeFile(patchFilename, packageJson.opam.patch, 'utf8');
    await execa.shell('patch -p1 < _esy_patch', {cwd: target});
  }
}

async function readJson(filename): any {
  const data = await fs.readFile(filename, 'utf8');
  const value = JSON.parse(data);
  return value;
}

async function writeJson(filename, value) {
  const data = JSON.stringify(value, null, 2);
  await fs.writeFile(filename, data, 'utf8');
}

async function lookupPackageCollection(packageName: string): Promise<PackageJsonCollection> {
  const packageRecordFilename = path.join(OPAM_METADATA_STORE, `${packageName}.json`)

  if (!await fs.exists(packageRecordFilename)) {
    throw new Error(`No package found: @opam/${packageName}`)
  }

  return await readJson(packageRecordFilename);
}

async function resolveFromOpam(spec, opts): Promise<any> {
  let [_opamScope, packageName] = spec.name.split('/')
  let packageCollection = await lookupPackageCollection(packageName);
  let packageJson = resolveVersion(packageCollection, spec);
  let opamInfo = packageJson.opam
  if (opamInfo.url) {
    let id = `${packageName}#${hash(opamInfo.url + hash(JSON.stringify(packageJson)))}`
    let resolution = {
      type: 'tarball',
      id,
      tarball: opamInfo.url,
      opam: {name: packageName, version: packageJson.version},
    }
    return {resolution}
  } else {
    let id = `${packageName}#${hash(JSON.stringify(packageJson))}`;
    let resolution = {
      type: 'tarball',
      id,
      tarball: `file:${require.resolve('./empty.tar.gz')}`,
      opam: {name: packageName, version: packageJson.version},
    }
    return {resolution}
  }
}

/**
 * Resolve version from a package collection given a package spec.
 */
function resolveVersion(packageCollection: PackageJsonCollection, spec): PackageJson {
  const versions = Object.keys(packageCollection.versions);

  if (spec.type === 'tag') {
    // Only allow "latest" tag
    if (spec.spec !== 'latest') {
      throw new Error(`No compatible version found: ${spec.raw}`);
    }
    const maxVersion = semver.maxSatisfying(versions, '*', true);
    return packageCollection.versions[maxVersion];

  } else {
    const maxVersion = semver.maxSatisfying(versions, spec.spec, true);
    if (maxVersion == null) {
      throw new Error(`No compatible version found: ${spec.raw}`);
    }
    return packageCollection.versions[maxVersion];
  }
}

export default function esyInstallCommand() {
  let streamParser = ndjson.parse();
  initLogger(streamParser);
  bole.output([
    {level: 'debug', stream: streamParser}
  ]);
  pnpm.install(installationSpec).then(
    () => {
      console.log(chalk.green('*** installation finished'));
    },
    (err) => {
      console.error(chalk.red(err.stack || err));
      process.exit(1);
    }
  );
}
