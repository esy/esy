const path = require('path');
const lockFile = require('./esy.lock/index.json');

function normalisePackageNames(n) {
  return n
    .replace(/@/g, '__AT__')
    .replace(/\//g, '__s__')
    .replace(/\./g, '__DOT__')
    .replace(/#/g, '__HASH__')
    .replace(/:/g, '__COLON__');
}

function compileMakefile(sources) {
  console.log(`${sourcesDir}:
${'\t'}mkdir -p ${sourcesDir};
`);
  for (key in sources) {
    let normalisedPackageName = normalisePackageNames(key);
    let [urlStrWithType, checksumCRC] = sources[key].split('#');
    let [algo, checksum] = checksumCRC.split(':');
    let parts = urlStrWithType.split(':');
    let sourceType = parts[0];
    let urlStr = parts.slice(1).join(':');
    console.log(`${normalisedPackageName}: ${sourcesDir}
${'\t'}curl -o ${path.join(sourcesDir, normalisedPackageName)} ${urlStr}
${'\t'}echo "${checksum} *${path.join(
      sourcesDir,
      normalisedPackageName,
    )}" | shasum -a ${algo.replace('sha', '')} -c
${'\t'}tar -xf ${path.join(sourcesDir, normalisedPackageName)} -C sources/
`);
  }
  console.log(`fetch-sources: ${Object.keys(sources).map(normalisePackageNames).join(' ')}
${'\t'}
${'\t'} echo "Fetched"`);
}

function visit(cur) {
  if (lockFile.node[cur].source.type === 'install') {
    let source = lockFile.node[cur].source.source[0];
    if (source !== 'no-source:' && !!source) {
      sources[cur] = source;
    }
  }
}

let root = lockFile.root;
let queue = new Set();
let cur = root;
let visited = new Map();
let sources = {};
let sourcesDir = 'sources';

do {
  if (!visited.get(cur)) {
    visit(cur);
    visited.set(cur, true);
  }
  lockFile.node[cur].dependencies.forEach((x) => queue.add(x));
  lockFile.node[cur].devDependencies.forEach((x) => queue.add(x));
  let queueAsArray = Array.from(queue.values());
  cur = queueAsArray.shift();
  queue = new Set(queueAsArray);
} while (cur);

compileMakefile(sources);
