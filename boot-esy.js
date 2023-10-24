const path = require('path');
let cp = require('child_process');
let fs = require('fs');
const lockFile = require('./esy.lock/index.json');

function normalisePackageNames(n) {
  return n
    .replace(/@/g, '__AT__')
    .replace(/\//g, '__s__')
    .replace(/\./g, '__DOT__')
    .replace(/#/g, '__HASH__')
    .replace(/:/g, '__COLON__');
}

function emitFetchSources(sources) {
  console.log(`${sourcesDir}:
${'\t'}mkdir -p ${sourcesDir};
`);
  for (key in sources) {
    let normalisedPackageName = normalisePackageNames(key);
    let [urlStrWithType, checksumCRC] = sources[key].split('#');
    let parts = urlStrWithType.split(':');
    let sourceType = parts[0];
    if (sourceType === 'archive') {
      let [algo, checksum] = checksumCRC.split(':');
      let parts = urlStrWithType.split(':');
      let sourceType = parts[0];
      let urlStr = parts.slice(1).join(':');
      let downloadedTarballFilePath =
        path.join(sourcesDir, normalisedPackageName) + '.tgz';
      console.log(`${normalisedPackageName}: ${sourcesDir}
${'\t'}sh ./boot/fetch-source.sh --checksum-algorithm=${algo} --checksum=${checksum} --output-file=${downloadedTarballFilePath} --url=${urlStr}
`);
    } else if (sourceType === 'github') {
      let matches = sources[key].match(
        /github:(?<org>[^\/]+)\/(?<repo>[^#:]+)(:(?<manifest>.*))?#(?<commit>.+)$/,
      );
      if (!matches) {
        throw new Error('Could not parse github source');
      }
      let {org, repo, manifest, commit} = matches.groups;
      console.log(`${normalisedPackageName}: ${sourcesDir}
${'\t'}sh ./boot/fetch-github.sh --org=${org} --repo=${repo} --manifest=${manifest} --commit=${commit} --clone-dir=sources/${normalisedPackageName}
`);
    }
  }
  console.log(`fetch-sources: ${Object.keys(sources).map(normalisePackageNames).join(' ')}
${'\t'}
${'\t'} echo "Fetched"`);
}

const Package = {
  nameOfLockEntry: (entry) => {
    let parts = entry.split('@');
    if (parts[0] !== '') {
      return parts[0];
    } else {
      return '@' + parts[1];
    }
  },
};

const Compile = {
  rule: ({target, deps, buildCommands}) =>
    `${target}: ${deps.join(' ')}\n\t${buildCommands
      .map((command) => command.join(' '))
      .join('; ')}`,
};

const Env = {
  render(env, {localStore, store, globalStorePrefix, sources, project}) {
    return Object.keys(env).reduce((acc, key) => {
      acc[key] = renderEsyVariables(env[key], {
        localStore,
        store,
        globalStorePrefix,
        sources,
        project,
      });
      return acc;
    }, {});
  },
  toString(env) {
    return Object.keys(env)
      .filter((key) => key !== 'SHELL') // TODO remove this
      .map((key) => {
        let v = env[key];
        if (v.indexOf(' ') !== -1) {
          v = `"${v}"`;
        }
        return `${key}=${v}`;
      })
      .join(' ');
  },
};

const esyBuildPlanCache = new Map();
function esyBuildPlan(packageName) {
  let cmd = 'esy build-plan';
  if (packageName) {
    let cachedResults = esyBuildPlanCache.get(packageName);
    if (cachedResults) {
      return cachedResults;
    }
    cmd = `${cmd} -p ${packageName}`;
  }
  let result = JSON.parse(cp.execSync(cmd).toString('utf-8'));
  if (packageName) {
    esyBuildPlanCache.set(packageName, result);
  }
  return result;
}

function renderEsyVariables(
  str,
  {localStore, store, globalStorePrefix, sources, project},
) {
  return str
    .replace(/%{globalStorePrefix}%/g, globalStorePrefix)
    .replace(/%{localStore}%/g, localStore)
    .replace(/%{store}%/g, store)
    .replace(/%{project}%/g, project)
    .replace('/store/s', '/store/i'); //HACK remove and start using rewritePrefix;
}

function traverse(
  makeFile,
  curInstallMap,
  {localStore, store, globalStorePrefix, sources, project},
  lockFile,
  packageID,
) {
  let {dependencies} =
    lockFile.node[packageID] || throwError(`Package name not found: ${packageID}`);
  let packageName = Package.nameOfLockEntry(packageID);
  let buildPlan = esyBuildPlan(packageName);
  let renderedEnv = Env.render(buildPlan.env, {
    localStore,
    store,
    globalStorePrefix,
    sources,
    project,
  });
  let buildsInSource =
    buildPlan.buildType == 'in-source' || buildPlan.buildPlan == '_build';
  let curRoot = renderedEnv['cur__root'].replace(
    path.join(process.env['HOME'], '.esy', 'source', 'i'),
    sources,
  );
  let curOriginalRoot = renderedEnv['cur__original_root'].replace(
    path.join(process.env['HOME'], '.esy', 'source', 'i'),
    sources,
  );
  let curToplevel = renderedEnv['cur__toplevel'];
  let curInstall = renderedEnv['cur__install'];
  let curInstallImmutable = curInstall.replace('/s/', '/i/');
  renderedEnv['cur__install'] = curInstallImmutable;
  curInstall = curInstallImmutable; // HACKY but useful
  let curTargetDir = renderedEnv['cur__target_dir'];
  let curStublibs = renderedEnv['cur__stublibs'];
  let curShare = renderedEnv['cur__share'];
  let curSbin = renderedEnv['cur__sbin'];
  let curMan = renderedEnv['cur__man'];
  let curLib = renderedEnv['cur__lib'];
  let curEtc = renderedEnv['cur__etc'];
  let curDoc = renderedEnv['cur__doc'];
  let curBin = renderedEnv['cur__bin'];
  let envFile = `${curTargetDir}.env`;

  let renderedEnvStr = Env.toString(renderedEnv);
  fs.writeFileSync(envFile, renderedEnvStr);
  curInstallMap.set(packageName, curInstallImmutable);

  let buildCommands = buildPlan.build
    .map((arg) =>
      arg.map((cmd) =>
        renderEsyVariables(cmd, {
          localStore,
          store,
          globalStorePrefix,
          sources,
          project,
        }),
      ),
    )
    .map((args) => {
      return [
        'env',
        '-i',
        '-P',
        `"${renderedEnv['PATH']}"`,
        '-S',
        '$(shell cat ' + envFile + ')',
      ].concat(args);
    });
  buildCommands = [['cd', curRoot]].concat(buildCommands);
  if (buildsInSource) {
    buildCommands = [['cp', '-R', `${curOriginalRoot}`, curRoot]].concat(buildCommands);
  } else {
    buildCommands = [['mkdir', '-p', curTargetDir]].concat(buildCommands);
  }
  buildCommands = [
    [
      'mkdir',
      '-p',
      curStublibs,
      curShare,
      curSbin,
      curMan,
      curLib,
      curEtc,
      curDoc,
      curBin,
    ],
  ]
    .concat(buildCommands)
    .concat([
      [
        'bash',
        '-c',
        `"if [ -f *.install ]; then env -i -P \\"${renderedEnv['PATH']}\\"  -S $(shell cat ${envFile}) dune install; fi"`,
      ],
    ]);
  return dependencies
    .reduce(
      (makeFile, dep) =>
        makeFile.concat(
          traverse(
            [],
            curInstallMap,
            {localStore, store, globalStorePrefix, sources, project},
            lockFile,
            dep,
          ),
        ),
      makeFile,
    )
    .concat([
      {
        target: curInstallImmutable,
        deps: dependencies.map(Package.nameOfLockEntry),
        buildCommands,
      },
      {
        target: packageName,
        deps: [curInstallImmutable],
        buildCommands: [],
      },
    ]);
}

function emitBuild(cwd) {
  const localStore = path.join(cwd, '_boot/store');
  const store = path.join(cwd, '_boot/store');
  const globalStorePrefix = path.join(cwd, '_boot/store');
  const sources = path.join(cwd, '_boot/sources');
  const project = cwd;

  const rootProjectBuildPlan = esyBuildPlan();
  const lockFile = require(cwd + '/esy.lock/index.json');
  /* type rule = { target, deps, build } */
  const makeFile /* list(rule) */ = [];
  console.log(
    traverse(
      makeFile,
      new Map(),
      {localStore, store, globalStorePrefix, sources, project},
      lockFile,
      lockFile.root,
    )
      .map(Compile.rule)
      .join('\n\n'),
  );
}

function compileMakefile(sources) {
  // emitFetchSources is deprecated. We use esy i --cache-tarballs-paths to fetch sources
  // emitFetchSources(sources);
  emitBuild(process.cwd());
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
