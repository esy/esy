/**
 * @flow
 */

import * as JSON5 from 'json5';
import * as fs from './lib/fs';
import * as path from './lib/path';
import invariant from 'invariant';

import {resolve as resolveNodeModule} from './util';
import type {PackageManifest} from './types';
import * as validate from './validate';

const MANIFEST_NAME_LIST = ['esy.json', 'package.json'];

type ManifestResult = {
  manifest: PackageManifest,
  filename: string,
};

export async function resolve(
  packageName: string,
  baseDirectory: string,
): Promise<?ManifestResult> {
  for (const manifestName of MANIFEST_NAME_LIST) {
    let manifestPath = null;
    try {
      manifestPath = await resolveNodeModule(
        `${packageName}/${manifestName}`,
        baseDirectory,
      );
    } catch (_err) {
      continue;
    }
    if (manifestPath != null) {
      const parse = manifestName === 'esy.json' ? JSON5.parse : JSON.parse;
      const manifest = await fs.readJson(manifestPath, parse);
      return {manifest: normalizeManifest(manifest), filename: manifestPath};
    }
  }
  return null;
}

export async function read(packagePath: string): Promise<ManifestResult> {
  for (const manifestName of MANIFEST_NAME_LIST) {
    const manifestPath = path.join(packagePath, manifestName);
    if (!await fs.exists(manifestPath)) {
      continue;
    }

    const parse = manifestName === 'esy.json' ? JSON5.parse : JSON.parse;
    const manifest = await fs.readJson(manifestPath, parse);
    return {manifest: normalizeManifest(manifest), filename: manifestPath};
  }

  invariant(
    false,
    'Unable to find manifest in %s: tried %s',
    packagePath,
    MANIFEST_NAME_LIST.join(', '),
  );
}

export function normalizeManifest(manifest: Object): PackageManifest {
  if (manifest.dependencies == null) {
    manifest.dependencies = {};
  }
  if (manifest.peerDependencies == null) {
    manifest.peerDependencies = {};
  }
  if (manifest.devDependencies == null) {
    manifest.devDependencies = {};
  }
  if (manifest.esy == null) {
    manifest.esy = {};
  }

  manifest.esy.build = normalizeCommand(manifest.esy.build);
  manifest.esy.install = normalizeCommand(manifest.esy.install);

  if (manifest.esy.exportedEnv == null) {
    manifest.esy.exportedEnv = {};
  }
  if (manifest.esy.buildsInSource == null) {
    manifest.esy.buildsInSource = false;
  }
  if (manifest.esy.sandboxType == null) {
    manifest.esy.sandboxType = 'project';
  } else {
    manifest.esy.sandboxType = validate.sandboxType(manifest.esy.sandboxType);
  }
  return manifest;
}

function normalizeCommand(
  command: null | string | Array<string | Array<string>>,
): Array<string | Array<string>> {
  if (command == null) {
    return [];
  } else if (!Array.isArray(command)) {
    return [command];
  } else {
    return command;
  }
}
