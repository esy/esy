/**
 * @flow
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');

import walkDir from 'walkdir';
import {copy, copySync} from 'fs-extra';

import {promisify} from './Promise';

// Promote some of the fs built-ins
export const stat: (path: string) => Promise<fs.Stats> = promisify(fs.stat);
export const lstat: (path: string) => Promise<fs.Stats> = promisify(fs.lstat);
export const readdir: (path: string, opts: void) => Promise<Array<string>> = promisify(
  fs.readdir,
);
export const rename: (oldPath: string, newPath: string) => Promise<void> = promisify(
  fs.rename,
);
export const exists: (path: string) => Promise<boolean> = promisify(fs.exists, true);
export const realpath: (p: string) => Promise<string> = promisify(fs.realpath);
export const readlink: (p: string) => Promise<string> = promisify(fs.readlink);
export const realpathSync: (p: string) => string = fs.realpathSync;
export const unlink: (prefix: string) => Promise<string> = promisify(fs.unlink);
export const readFileBuffer: (p: string) => Promise<Buffer> = promisify(fs.readFile);
export const writeFile: (
  path: string,
  data: Buffer | string,
  encdogin?: string,
) => Promise<void> = promisify(fs.writeFile);
export const chmod: (path: string, mode: number | string) => Promise<void> = promisify(
  fs.chmod,
);
export const writeFileSync = fs.writeFileSync;

// Promote 3rd-party fs utils
export const rmdir: (p: string) => Promise<void> = promisify(require('rimraf'));
export const rmdirSync: (p: string) => void = require('rimraf').sync;
export const mkdirp: (path: string) => Promise<void> = promisify(require('mkdirp'));

// mkdtemp
export const _mkdtemp: string => Promise<string> = promisify(fs.mkdtemp);
export const _mkdtempSync = fs.mkdtempSync;

export function mkdtemp(prefix: string) {
  const root = os.tmpdir();
  return _mkdtemp(path.join(root, prefix));
}

// copydir
const _copydir: (
  string,
  string,
  {filter?: string => boolean},
) => Promise<void> = promisify(copy);

export {copy};

export async function copydir(
  from: string,
  to: string,
  params?: {
    exclude?: string[],
  } = {},
): Promise<void> {
  await _copydir(from, to, {
    filter: filename => !(params.exclude && params.exclude.includes(filename)),
  });
}

export function copydirSync(
  from: string,
  to: string,
  params?: {
    exclude?: string[],
  } = {},
): void {
  copySync(from, to, {
    filter: filename => !(params.exclude && params.exclude.includes(filename)),
  });
}

export async function readFile(p: string): Promise<string> {
  const data = await readFileBuffer(p);
  return data.toString('utf8');
}

export function readFileSync(p: string) {
  return fs.readFileSync(p, 'utf8');
}

export async function readJson(p: string, parse: string => Function = JSON.parse) {
  const data = await readFile(p);
  return parse(data);
}

export function readJsonSync(p: string, parse: string => Function = JSON.parse) {
  const data = readFileSync(p);
  return parse(data);
}

export const fsSymlink: (
  target: string,
  path: string,
  type?: 'dir' | 'file' | 'junction',
) => Promise<void> = promisify(fs.symlink);

export async function symlink(src: string, dest: string): Promise<void> {
  try {
    const stats = await lstat(dest);

    if (stats.isSymbolicLink() && (await exists(dest))) {
      const resolved = await realpath(dest);
      if (resolved === src) {
        return;
      }
    }

    await unlink(dest);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      throw err;
    }
  }

  try {
    if (process.platform === 'win32') {
      // use directory junctions if possible on win32, this requires absolute paths
      await fsSymlink(src, dest, 'junction');
    } else {
      // use relative paths otherwise which will be retained if the directory is moved
      const relative = path.relative(
        fs.realpathSync(path.dirname(dest)),
        fs.realpathSync(src),
      );
      await fsSymlink(relative, dest);
    }
  } catch (err) {
    if (err.code === 'EEXIST') {
      // race condition
      await symlink(src, dest);
    } else {
      throw err;
    }
  }
}

export type WalkFiles = Array<{
  relative: string,
  absolute: string,
  basename: string,
  mtime: number,
  stats: fs.Stats,
}>;

export async function walk(
  dir: string,
  relativeDir?: ?string,
  ignoreBasenames?: Set<string> = new Set(),
): Promise<WalkFiles> {
  let files = [];

  let filenames = await readdir(dir);
  if (ignoreBasenames.size) {
    filenames = filenames.filter(name => !ignoreBasenames.has(name));
  }

  for (const name of filenames) {
    const relative = relativeDir ? path.join(relativeDir, name) : name;
    const loc = path.join(dir, name);
    const stats = await lstat(loc);

    files.push({
      relative,
      basename: name,
      absolute: loc,
      mtime: +stats.mtime,
      stats,
    });

    if (stats.isDirectory()) {
      files = files.concat(await walk(loc, relative, ignoreBasenames));
    }
  }

  return files;
}

export function findMaxMtime(
  dirname: string,
  options?: {ignore?: string => boolean} = {},
): Promise<number> {
  const ignore = options.ignore ? options.ignore : _filename => false;
  let maxMtime = -Infinity;

  return new Promise((resolve, reject) => {
    const w = walkDir(dirname);
    w.on('path', (name, stat) => {
      if (ignore(name)) {
        w.ignore(name);
      } else if (stat.isFile()) {
        const mtime = Math.floor(stat.mtime.getTime() / 1000);
        if (mtime > maxMtime) {
          maxMtime = mtime;
        }
      }
    });
    w.on('end', () => {
      resolve(maxMtime);
    });
    w.on('error', error => {
      reject(error);
    });
  });
}
