/**
 * @flow
 */

export {Promise};

export {default as PromiseQueue} from 'p-queue';

export function promisify(fn: Function, firstData?: boolean): () => Promise<any> {
  return function(...args): Promise<any> {
    return new Promise(function(resolve, reject) {
      args.push(function(err, ...result) {
        let res = result;

        if (result.length <= 1) {
          res = result[0];
        }

        if (firstData) {
          res = err;
          err = null;
        }

        if (err) {
          reject(err);
        } else {
          resolve(res);
        }
      });

      fn.apply(null, args);
    });
  };
}

export function promisifyObject(obj: {
  [key: string]: Function,
}): {
  [key: string]: () => Promise<any>,
} {
  const promisedObj = {};
  for (const key in obj) {
    promisedObj[key] = promisify(obj[key]);
  }
  return promisedObj;
}
