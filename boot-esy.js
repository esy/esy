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
function esyBuildPlan(cwd, packageName) {
  if (packageName === 'setup-esy-installer') {
    return JSON.parse(` {
  "id": "setup_esy_installer-fb3bf850",
  "name": "setup-esy-installer",
  "version": "github:ManasJayanth/esy-boot-installer#beee8a4775846651c958946ec1d6919e54bd49bc",
  "sourceType": "immutable",
  "buildType": "in-source",
  "build": [
    [
      "make", "PREFIX=%{store}%/s/setup_esy_installer-fb3bf850",
      "esy-installer"
    ]
  ],
  "install": [
    [ "make", "PREFIX=%{store}%/s/setup_esy_installer-fb3bf850", "install" ]
  ],
  "sourcePath": "${cwd}/_boot/sources/esy-boot-installer",
  "rootPath": "%{globalStorePrefix}%/3/b/setup_esy_installer-fb3bf850",
  "buildPath": "%{globalStorePrefix}%/3/b/setup_esy_installer-fb3bf850",
  "stagePath": "%{store}%/s/setup_esy_installer-fb3bf850",
  "installPath": "%{store}%/i/setup_esy_installer-fb3bf850",
  "env": {
    "cur__version": "github:ManasJayanth/esy-boot-installer#beee8a4775846651c958946ec1d6919e54bd49bc",
    "cur__toplevel": "%{store}%/s/setup_esy_installer-fb3bf850/toplevel",
    "cur__target_dir": "%{globalStorePrefix}%/3/b/setup_esy_installer-fb3bf850",
    "cur__stublibs": "%{store}%/s/setup_esy_installer-fb3bf850/stublibs",
    "cur__share": "%{store}%/s/setup_esy_installer-fb3bf850/share",
    "cur__sbin": "%{store}%/s/setup_esy_installer-fb3bf850/sbin",
    "cur__root": "%{globalStorePrefix}%/3/b/setup_esy_installer-fb3bf850",
     "cur__original_root": "${cwd}/_boot/sources/esy-boot-installer",
    "cur__name": "setup-esy-installer",
    "cur__man": "%{store}%/s/setup_esy_installer-fb3bf850/man",
    "cur__lib": "%{store}%/s/setup_esy_installer-fb3bf850/lib",
    "cur__jobs": "4",
    "cur__install": "%{store}%/s/setup_esy_installer-fb3bf850",
    "cur__etc": "%{store}%/s/setup_esy_installer-fb3bf850/etc",
    "cur__doc": "%{store}%/s/setup_esy_installer-fb3bf850/doc",
    "cur__dev": "false",
    "cur__bin": "%{store}%/s/setup_esy_installer-fb3bf850/bin",
    "SHELL": "env -i /bin/bash --norc --noprofile",
    "PATH": "%{store}%/i/ocaml-4.12.0-3a04ec8f/bin::/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "OCAML_TOPLEVEL_PATH": "%{store}%/i/ocaml-4.12.0-3a04ec8f/lib/ocaml",
    "OCAMLPATH": "%{store}%/i/ocaml-4.12.0-3a04ec8f/lib:",
    "OCAMLLIB": "%{store}%/i/ocaml-4.12.0-3a04ec8f/lib/ocaml",
    "OCAMLFIND_LDCONF": "ignore",
    "OCAMLFIND_DESTDIR": "%{store}%/s/setup_esy_installer-fb3bf850/lib",
    "MAN_PATH": "%{store}%/i/ocaml-4.12.0-3a04ec8f/man:",
    "CAML_LD_LIBRARY_PATH": "%{store}%/i/ocaml-4.12.0-3a04ec8f/lib/ocaml/stublibs:%{store}%/i/ocaml-4.12.0-3a04ec8f/lib/ocaml:"
  },
  "jbuilderHackEnabled": false,
  "depspec": "dependencies(self)"
}`);
  }

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
  cwd,
) {
  let dependencies;
  if (packageID === 'setup-esy-installer@vvv@hhh') {
    dependencies = Object.keys(lockFile.node).filter((k) => k.startsWith('ocaml@'));
  } else {
    dependencies =
      (lockFile.node[packageID] && lockFile.node[packageID].dependencies) ||
      throwError(`Package name not found: ${packageID}`);
  }
  let packageName = Package.nameOfLockEntry(packageID);
  if (makeFile.get(packageName)) {
    return makeFile;
  } else {
    let buildPlan = esyBuildPlan(cwd, packageName);
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
    let pathFile = `${curTargetDir}.path`;

    let renderedEnvStr = Env.toString(renderedEnv);
    fs.writeFileSync(envFile, renderedEnvStr);
    fs.writeFileSync(pathFile, renderedEnv['PATH']);
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
        return [`${cwd}/boot/build-env.sh`, envFile, pathFile, `"${args.join(' ')}"`];
      });
    buildCommands = [['cd', curRoot]].concat(buildCommands);
    if (buildsInSource) {
      buildCommands = [
        ['rm', '-rf', curRoot],
        ['cp', '-R', `${curOriginalRoot}`, curRoot],
      ].concat(buildCommands);
    } else {
      buildCommands = [
        ['rm', '-rf', curTargetDir],
        ['mkdir', '-p', curTargetDir],
      ].concat(buildCommands);
    }
    buildCommands = [['bash', `${cwd}/boot/prepare-build.sh`, curInstall]]
      .concat(buildCommands)
      .concat(
        buildPlan.install && buildPlan.install.length !== 0
          ? buildPlan.install
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
                  `${cwd}/boot/build-env.sh`,
                  envFile,
                  pathFile,
                  `"${args.join(' ')}"`,
                ];
              })
          : [
              [
                'bash',
                `${cwd}/boot/install-artifacts.sh`,
                envFile,
                pathFile,
                path.join(
                  cwd,
                  '_boot/store/i/setup_esy_installer-fb3bf850/bin/esy-installer',
                ), // TODO replace this hardcoded path
                curInstallImmutable,
                packageName,
              ],
            ],
      );
    // A trick to make sure setup-esy-installer is run before everything else, including Dune
    if (packageName === '@opam/dune') {
      dependencies.push('setup-esy-installer@vvv@hhh');
    }

    makeFile = dependencies.reduce((makeFile, dep) => {
      return traverse(
        makeFile,
        curInstallMap,
        {localStore, store, globalStorePrefix, sources, project},
        lockFile,
        dep,
        cwd,
      );
    }, makeFile);

    let deps = dependencies.map(Package.nameOfLockEntry);

    makeFile.set(curInstallImmutable, {
      target: curInstallImmutable,
      deps,
      buildCommands,
    });

    makeFile.set(packageName, {
      target: packageName,
      deps: [curInstallImmutable],
      buildCommands: [],
    });

    return makeFile;
  }
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
  const makeFile /* list(rule) */ = new Map();
  console.log(
    Array.from(
      traverse(
        makeFile,
        new Map(),
        {localStore, store, globalStorePrefix, sources, project},
        lockFile,
        lockFile.root,
        cwd,
      ).values(),
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
