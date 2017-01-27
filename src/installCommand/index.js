/**
 * @flow
 */

import type {Sandbox} from '../Sandbox';

import {tmpdir} from 'os';
import path from 'path';
import crypto  from 'crypto';
import fs from 'mz/fs';
import execa from 'execa';
import semver from 'semver';
import tempfile from 'tempfile';
import chalk from 'chalk';
import ndjson from 'ndjson';
import bole from 'bole';
import mkdirp from 'mkdirp-then';
import * as pnpm from '@andreypopp/pnpm';

import {hash} from '../Utility';
import initLogger from './logger';

export type PackageJsonCollection = {
  versions: {
    [name: string]: PackageJson;
  }
};

type File = {
  name: string;
  content: string;
};

export type PackageJson = {
  name: string;
  version: string;
  opam: {
    url: string;
    files?: Array<File>;
    checksum?: string;
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
        await fetchFromOpam(target, resolution, opts.got);
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

        await putFiles(packageJson, target);
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

async function putFiles(packageJson: PackageJson, target: string) {
  if (packageJson.opam.files) {
    await Promise.all(packageJson.opam.files.map(file =>
      fs.writeFile(path.join(target, file.name), file.content, 'utf8')));
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

async function fetchFromOpam(target, resolution, fetcher) {
  if (resolution.tarball === 'empty') {
    await mkdirp(target);
  } else {
    const basename = path.basename(resolution.tarball);
    const stage = tempfile(basename);

    await mkdirp(stage);
    await mkdirp(target);

    const filename = path.join(stage, basename);
    const stream = await fetcher.getStream(resolution.tarball);
    await saveStreamToFile(stream, filename, resolution.checksum);
    await unpackTarball(filename, target);
  }
}

async function saveStreamToFile(stream, filename, md5checksum = null) {
  let hasher = crypto.createHash('md5');
  return new Promise((resolve, reject) => {
    let out = fs.createWriteStream(filename);
    stream
      .on('data', chunk => {
        if (md5checksum != null) {
          hasher.update(chunk);
        }
      })
      .pipe(out)
      .on('error', err => {
        reject(err);
      })
      .on('finish', () => {
        let actualChecksum = hasher.digest('hex');
        if (md5checksum != null) {
          if (actualChecksum !== md5checksum) {
            reject(new Error(`Incorrect md5sum (expected ${md5checksum}, got ${actualChecksum})`))
            return;
          }
        }
        resolve();
      })
    if (stream.resume) {
      stream.resume();
    }
  });
}

async function unpackTarball(filename, target) {
  let isGzip = filename.endsWith('.tar.gz') || filename.endsWith('.tgz');
  let isBzip2 = filename.endsWith('.tbz') || filename.endsWith('.tar.bz2');
  if (!isGzip && !isBzip2) {
    throw new Error(`unknown tarball type: ${filename}`);
  }
  await execa('tar', [
    '-x',
    isGzip ? '-z' : '-j',
    '-f', filename,
    '--strip-components', '1',
    '-C', target
  ]);
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
      checksum: opamInfo.checksum || null,
      opam: {name: packageName, version: packageJson.version},
    }
    return {resolution}
  } else {
    let id = `${packageName}#${hash(JSON.stringify(packageJson))}`;
    let resolution = {
      type: 'tarball',
      id,
      tarball: 'empty',
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

function initLogging() {
  let streamParser = ndjson.parse();
  initLogger(streamParser);
  bole.output([
    {level: 'debug', stream: streamParser}
  ]);
}

export function esyInstallCommand() {
  initLogging();
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

export function esyAddCommand(...installPackages: Array<string>) {
  initLogging();
  pnpm.installPkgs(installPackages, {
    ...installationSpec,
    save: true
  }).then(
    () => {
      console.log(chalk.green('*** installation finished'));
    },
    (err) => {
      console.error(chalk.red(err.stack || err));
      process.exit(1);
    }
  );
}
