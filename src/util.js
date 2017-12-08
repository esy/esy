/**
 * @flow
 */

import resolveBase from 'resolve';
import * as stream from 'stream';
import * as fs from './lib/fs';

export function resolve(packageName: string, baseDirectory: string): Promise<string> {
  return new Promise((resolve, reject) => {
    resolveBase(packageName, {basedir: baseDirectory}, (err, resolution) => {
      if (err) {
        reject(err);
      } else {
        resolve(resolution);
      }
    });
  });
}

export async function resolveToRealpath(
  packageName: string,
  baseDirectory: string,
): Promise<string> {
  const resolution = await resolve(packageName, baseDirectory);
  return fs.realpath(resolution);
}

export function normalizePackageName(name: string): string {
  return (
    name
      .toLowerCase()
      .replace(/@/g, '')
      .replace(/_+/g, matched => matched + '__')
      .replace(/\//g, '__slash__')
      // Add two underscores to every group we see.
      .replace(/\./g, '__dot__')
      .replace(/\-/g, '_')
  );
}
