/**
 * @flow
 */

function mapObject<S: *, F: <V>(v: V) => *>(obj: S, f: F): $ObjMap<S, F> {
  let nextObj = {};
  for (var k in obj) {
    nextObj[k] = f(obj[k], k);
  }
  return nextObj;
}

function flattenArray<T>(arrayOfArrays: Array<Array<T>>): Array<T> {
  return [].concat(...arrayOfArrays);
}

module.exports = {
  mapObject,
  flattenArray,
};
