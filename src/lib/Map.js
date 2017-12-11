/**
 * @flow
 */

export {Map};

export function create<K, V>(v?: Array<[K, V]>): Map<K, V> {
  return new Map(v);
}

export function mapValues<K, V1, V2>(f: (V1, K) => V2, map: Map<K, V1>): Map<K, V2> {
  const result = create();
  for (const [k, v] of map.entries()) {
    result.set(k, f(v, k));
  }
  return result;
}
