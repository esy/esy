// esy i --cache-tarballs-path=_esy-sources
// cd _esy-sources
// for i in $(ls *.tgz); do mkdir ${i%.tgz}; tar -xf ${i} -C ${i%.tgz}; done
let cp = require('child_process');
let fs = require('fs');

let Package, esyBuildPlanStr, esyBuildPlan, lockFile, makeFile, Compile;
Package = {
  nameOfLockEntry: (entry) => entry.split('@')[0],
};

esyBuildPlanStr = cp.execSync('esy build-plan').toString('utf-8');

esyBuildPlan = JSON.parse(esyBuildPlanStr);

lockFile = require('./esy.lock/index.json');
Object.keys(lockFile);
Package.nameOfLockEntry(lockFile.root);

/* type rule = { target, deps, build } */
makeFile /* list(rule) */ = [];

Compile = {
  rule: ({target, deps, buildCommands}) => `${target}: ${deps.join(' ')}
${buildCommands.map((command) => '\t' + command.join(' ')).join('\n')}`,
};

Compile.rule({
  target: 'foo',
  deps: ['bar', 'baz'],
  buildCommands: [
    ['dune', 'build', '-p', 'foo'],
    ['dune', 'build', '-p', 'bar'],
  ],
});

function throwError(packageName) {
  throw `Package name not found: ${packageName}`;
}

function traverse(makeFile, lockFile, packageName) {
  let {dependencies} = lockFile.node[packageName] || throwError(packageName);
  return dependencies
    .reduce((makeFile, dep) => makeFile.concat(traverse([], lockFile, dep)), makeFile)
    .concat([
      {
        target: packageName,
        deps: dependencies,
        buildCommands: [
          ['echo', 'foo'],
          ['echo', 'bar', 'baz'],
        ],
      },
    ]);
}

fs.writeFileSync(
  'boot.Makefile',
  traverse([], lockFile, lockFile.root).map(Compile.rule).join('\n\n'),
);
