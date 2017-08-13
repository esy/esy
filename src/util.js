/**
 * @flow
 */

// Using ES "import" syntax triggers deprecation warnings in Node
const crypto = require('crypto');
import resolveBase from 'resolve';
import * as stream from 'stream';
import * as fs from './lib/fs';

export function mapObject<S: *, F: (*, string) => *>(obj: S, f: F): $ObjMap<S, F> {
  const nextObj = {};
  for (const k in obj) {
    nextObj[k] = f(obj[k], k);
  }
  return nextObj;
}

export function flattenArray<T>(arrayOfArrays: Array<Array<T>>): Array<T> {
  return [].concat(...arrayOfArrays);
}

export function computeHash(str: string, algo: string = 'sha1'): string {
  const hash = crypto.createHash(algo);
  hash.update(str);
  return hash.digest('hex');
}

export function setDefaultToMap<K, V>(
  map: Map<K, V>,
  key: K,
  makeDefaultValue: () => V,
): V {
  const existingValue = map.get(key);
  if (existingValue == null) {
    const value = makeDefaultValue();
    map.set(key, value);
    return value;
  } else {
    return existingValue;
  }
}

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

export function filterMap<K, V>(map: Map<K, V>, filter: (V, K) => boolean): Map<K, V> {
  const res: Map<K, V> = new Map();
  for (const [k, v] of map.entries()) {
    if (filter(v, k)) {
      res.set(k, v);
    }
  }
  return res;
}

export function mapValuesMap<K, V, V2>(map: Map<K, V>, mapper: (V, K) => V2): Map<K, V2> {
  const res: Map<K, V2> = new Map();
  for (const [k, v] of map.entries()) {
    res.set(k, mapper(v, k));
  }
  return res;
}

export function mergeIntoMap<K, V>(
  src: Map<K, V>,
  from: Map<K, V>,
  merge?: (prev: V, override: V, name: K) => V,
) {
  for (const [k, v] of from.entries()) {
    const prev = src.get(k);
    if (prev != null && merge) {
      src.set(k, merge(prev, v, k));
    } else {
      src.set(k, v);
    }
  }
}

export function interleaveStreams(...sources: stream.Readable[]): stream.Readable {
  const output = new stream.PassThrough();
  let streamActiveNumber = sources.length;
  for (const source of sources) {
    source.on('error', err => output.emit(err));
    source.once('end', () => {
      streamActiveNumber -= 1;
      if (streamActiveNumber === 0) {
        output.end('', 'ascii');
      }
    });
    source.pipe(output, {end: false});
  }
  return output;
}

export function endWritableStream(s: stream.Writable): Promise<void> {
  return new Promise((resolve, reject) => {
    s.write('', 'ascii', err => {
      s.end();
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}

export function writeIntoStream(s: stream.Writable, data: string): Promise<void> {
  return new Promise((resolve, reject) => {
    s.write(data, 'ascii', err => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}
