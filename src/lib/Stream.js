/**
 * @flow
 */

import * as stream from 'stream';

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
