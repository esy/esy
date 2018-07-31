/**
 * Utilities to generate fixtures.
 *
 * @flow
 */

const fs = require('fs-extra');
const path = require('path');

export type Fixture = Array<FixtureItem>;
export type FixtureItem = FixtureDir | FixtureFile | FixtureFileCopy | FixtureSymlink;
export type FixtureDir = {
  type: 'dir',
  name: string,
  items: Array<FixtureItem>,
};
export type FixtureFile = {
  type: 'file',
  name: string,
  data: string,
};
export type FixtureFileCopy = {
  type: 'file-copy',
  name: string,
  path: string,
};
export type FixtureSymlink = {
  type: 'symlink',
  name: string,
  path: string,
};

function dir(name: string, ...items: Array<FixtureItem>): FixtureDir {
  return {type: 'dir', name, items};
}

function file(name: string, data: string): FixtureFile {
  return {type: 'file', name, data};
}

function symlink(name: string, path: string): FixtureSymlink {
  return {type: 'symlink', name, path};
}

function packageJson(json: Object) {
  return file('package.json', JSON.stringify(json, null, 2));
}

async function initialize(p: string, fixture: FixtureItem) {
  if (fixture.type === 'file') {
    await fs.writeFile(path.join(p, fixture.name), fixture.data);
  } else if (fixture.type === 'file-copy') {
    await fs.copyFile(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'symlink') {
    await fs.symlink(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'dir') {
    const nextp = path.join(p, fixture.name);
    await fs.mkdir(nextp);
    await Promise.all(fixture.items.map(item => initialize(nextp, item)));
  } else {
    throw new Error('unknown fixture ' + JSON.stringify(fixture));
  }
}

module.exports = {
  initialize,
  dir,
  file,
  symlink,
  packageJson,
};
