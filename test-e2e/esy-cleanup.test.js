// @flow

const outdent = require('outdent');
const helpers = require('./test/helpers.js');
const path = require('path');
const fs = require('./test/fs.js');
const {createTestSandbox, defineNpmPackage, packageJson, test, isWindows} = helpers;

const testFolder = './tests/';

class Path {
  constructor(value) {
    this.path = value.split(/[\/\\]/);
  }
  equals(other) {
    if (this.path === other.path) return true;
    if (this.path == null || other.path == null) return false;
    if (this.path.length !== other.path.length) return false;
    for (var i = 0; i < this.path.length; ++i) {
      if (this.path[i] !== other.path[i]) return false;
    }
    return true;
  }
  toString() {
    return this.path.join('/');
  }
}

class EsyInstallCacheEntry {
  constructor(entry) {
    let matches = entry.match(/(?<entryBaseName>[^\-]+-[^\-]+)+-(?<hash>[a-h0-9]+)$/);
    if (matches) {
      let {entryBaseName, hash} = matches.groups;
      this.entry = entryBaseName;
      this.hash = hash;
    }
  }
  toString() {
    return `[Cache entry base name: ${this.entry} hash: ${this.hash}]`;
  }
  equals(other) {
    // It's not important that hashes match
    return this.entry === other.entry;
  }
}

class EsySourceCacheEntry {
  constructor(entry) {
    let groups = entry.split('__');
    this.hash = groups.pop();
    this.version = groups.pop();
    this.name = groups.join('__');
  }
  toString() {
    return `[Cache entry name: ${this.name} version:{this.version} hash: ${this.hash}]`;
  }
  equals(other) {
    // It's not important that hashes match
    return this.name === other.name && this.version === other.version;
  }
}

function areInstallCacheEntriesEqual(a, b) {
  const isAEsyCacheEntry = a instanceof EsyInstallCacheEntry;
  const isBEsyCacheEntry = b instanceof EsyInstallCacheEntry;

  if (isAEsyCacheEntry && isBEsyCacheEntry) {
    return a.equals(b);
  } else if (isAEsyCacheEntry !== isBEsyCacheEntry) {
    return false;
  } else {
    return undefined;
  }
}

function areSourceCacheEntriesEqual(a, b) {
  const isAEsyCacheEntry = a instanceof EsySourceCacheEntry;
  const isBEsyCacheEntry = b instanceof EsySourceCacheEntry;

  if (isAEsyCacheEntry && isBEsyCacheEntry) {
    return a.equals(b);
  } else if (isAEsyCacheEntry !== isBEsyCacheEntry) {
    return false;
  } else {
    return undefined;
  }
}

function arePathsEqual(a, b) {
  const isAPath = a instanceof Path;
  const isBPath = b instanceof Path;

  if (isAPath && isBPath) {
    return a.equals(b);
  } else if (isAPath !== isBPath) {
    return false;
  } else {
    return undefined;
  }
}

expect.addEqualityTesters([
  areInstallCacheEntriesEqual,
  areSourceCacheEntriesEqual,
  arePathsEqual,
]);

function toPath(l) {
  if (l instanceof Array) {
    return l.map((x) => new Path(x));
  }
}

describe('cleanup command', () => {
  test(`should add project path to project.json`, async () => {
    const fixture = [
      helpers.packageJson({name: 'root', version: '1.0.0', esy: {}, dependencies: {}}),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy('install');

    expect(toPath(await fs.readJson(p.esyPrefixPath + '/projects.json'))).toEqual(
      toPath([p.projectPath]),
    );
  });

  test(`should skip adding project if it is already added`, async () => {
    const fixture = [
      helpers.packageJson({name: 'root', version: '1.0.0', esy: {}, dependencies: {}}),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await fs.writeJson(p.esyPrefixPath + '/projects.json', [p.projectPath]);
    const {stderr} = await p.esy('install');

    expect(toPath(await fs.readJson(p.esyPrefixPath + '/projects.json'))).toEqual(
      toPath([p.projectPath]),
    );
  });

  test(`should default to all paths in projects.json if not path provided`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          [`one-fixed-dep`]: `1.0.0`,
          [`one-range-dep`]: `1.0.0`,
        },
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('install');

    const {stderr} = await p.esy('cleanup');

    // const {stderr, stdout} = await p.esy("ls-builds -T");

    await expect(stderr).toMatch(/info cleanup/);
  });

  it('cleanup - more workflows', async () => {
    let sandbox = await createTestSandbox();
    let projectsJsonPath = path.join(sandbox.esyPrefixPath, 'projects.json');
    await sandbox.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
      esy: {
        build: 'true',
      },
    });
    await sandbox.defineNpmPackage({
      name: 'depDep',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
    });
    await sandbox.defineNpmPackage({
      name: 'depDep',
      version: '2.0.0',
      esy: {
        build: 'true',
      },
    });
    await sandbox.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {dep: `1.0.0`},
        esy: {
          build: 'true',
        },
      }),
    );
    await sandbox.esy();
    let installCache = await fs.readdir(path.join(sandbox.esyStorePath, 'i'));
    function toEsyInstallCacheEntry(l) {
      return l.map((x) => new EsyInstallCacheEntry(x));
    }
    expect(toEsyInstallCacheEntry(installCache)).toEqual(
      toEsyInstallCacheEntry(['dep-1.0.0-e3915c0b', 'depdep-1.0.0-a4fc2165']),
    );
    expect(
      toEsyInstallCacheEntry(
        await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i')),
      ),
    ).toEqual(
      toEsyInstallCacheEntry(['dep__1.0.0__b35a2f2d', 'depdep__1.0.0__37e7a60c']),
    );
    await sandbox.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {depDep: `2.0.0`},
        esy: {
          build: 'true',
        },
      }),
    );
    await sandbox.esy();
    expect(toPath(require(projectsJsonPath))).toEqual(toPath([sandbox.projectPath]));
    expect(
      toEsyInstallCacheEntry(await fs.readdir(path.join(sandbox.esyStorePath, 'i'))),
    ).toEqual(
      toEsyInstallCacheEntry([
        'dep-1.0.0-e3915c0b',
        'depdep-1.0.0-a4fc2165',
        'depdep-2.0.0-d88993ca',
      ]),
    );
    expect(
      toEsyInstallCacheEntry(
        await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i')),
      ),
    ).toEqual(
      toEsyInstallCacheEntry([
        'dep__1.0.0__b35a2f2d',
        'depdep__1.0.0__37e7a60c',
        'depdep__2.0.0__8560b5e1',
      ]),
    );
    await sandbox.esy('cleanup');
    expect(
      toEsyInstallCacheEntry(await fs.readdir(path.join(sandbox.esyStorePath, 'i'))),
    ).toEqual(toEsyInstallCacheEntry(['depdep-2.0.0-d88993ca']));
    expect(
      toEsyInstallCacheEntry(
        await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i')),
      ),
    ).toEqual(toEsyInstallCacheEntry(['depdep__2.0.0__8560b5e1']));
    await sandbox.esy('cleanup');
    expect(
      toEsyInstallCacheEntry(await fs.readdir(path.join(sandbox.esyStorePath, 'i'))),
    ).toEqual(toEsyInstallCacheEntry(['depdep-2.0.0-d88993ca']));
    expect(
      toEsyInstallCacheEntry(
        await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i')),
      ),
    ).toEqual(toEsyInstallCacheEntry(['depdep__2.0.0__8560b5e1']));
    await fs.rename(projectsJsonPath, `${projectsJsonPath}.bak`);
    await sandbox.esy('cleanup');
    expect(
      toEsyInstallCacheEntry(await fs.readdir(path.join(sandbox.esyStorePath, 'i'))),
    ).toEqual(toEsyInstallCacheEntry(['depdep-2.0.0-d88993ca']));
    expect(
      toEsyInstallCacheEntry(
        await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i')),
      ),
    ).toEqual(toEsyInstallCacheEntry(['depdep__2.0.0__8560b5e1']));
    // TODO: when the last/one-and-only project gets removed,
    // cleanup command receives an empty list. This is confusing because
    // it could be that projects.json wasn't present in the first place.
    // If a projects.json is missing, cleanup with no args must be
    // a noop - not assume that everything can be deleted!
    // ----
    // await fs.rename(`${projectsJsonPath}.bak`, projectsJsonPath);
    // await sandbox.cd('..');
    // await fs.remove(sandbox.projectPath);
    // await sandbox.esy('cleanup');
    // expect(await fs.readdir(path.join(sandbox.esyStorePath, 'i'))).toEqual([]);
    // expect(await fs.readdir(path.join(sandbox.esyPrefixPath, 'source', 'i'))).toEqual([]);
  });
});
