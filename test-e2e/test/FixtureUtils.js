/**
 * Utilities to generate fixtures.
 *
 * @flow
 */

const fs = require('fs-extra');
const path = require('path');

/*::
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
*/

function dir(
  name /*: string | string[] */,
  ...items /*: Array<FixtureItem>*/
) /*: FixtureDir*/ {
  if (Array.isArray(name)) {
    if (name.length === 0) {
      throw new Error('invalid fixture');
    } else if (name.length === 1) {
      return dir(name[0], ...items);
    } else {
      return dir(name[0], dir(name.slice(1), ...items));
    }
  } else {
    return {type: 'dir', name, items};
  }
}

function file(name /*: string*/, data /*: string*/) /*: FixtureFile*/ {
  return {type: 'file', name, data};
}

function json(name /*: string*/, json /*: Object*/) /*: FixtureFile*/ {
  const data = JSON.stringify(json, null, 2);
  return {type: 'file', name, data};
}

function symlink(name /*: string*/, path /*: string*/) /*: FixtureSymlink*/ {
  return {type: 'symlink', name, path};
}

function packageJson(json /*: Object*/) {
  return file('package.json', JSON.stringify(json, null, 2));
}

async function layout(p /*: string*/, fixture /*: FixtureItem*/) {
  if (fixture.type === 'file') {
    await fs.writeFile(path.join(p, fixture.name), fixture.data);
  } else if (fixture.type === 'file-copy') {
    await fs.copyFile(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'symlink') {
    await fs.symlink(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'dir') {
    const nextp = path.join(p, fixture.name);
    await fs.mkdir(nextp);
    await Promise.all(fixture.items.map(item => layout(nextp, item)));
  } else {
    throw new Error('unknown fixture ' + JSON.stringify(fixture));
  }
}

function layoutSync(p /*: string*/, fixture /*: FixtureItem*/) {
  if (fixture.type === 'file') {
    fs.writeFileSync(path.join(p, fixture.name), fixture.data);
  } else if (fixture.type === 'file-copy') {
    fs.copyFileSync(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'symlink') {
    fs.symlinkSync(fixture.path, path.join(p, fixture.name));
  } else if (fixture.type === 'dir') {
    const nextp = path.join(p, fixture.name);
    fs.mkdirSync(nextp);
    fixture.items.forEach(item => layoutSync(nextp, item));
  } else {
    throw new Error('unknown fixture ' + JSON.stringify(fixture));
  }
}

function initialize(p /*: string*/, fixture /*: Fixture*/) {
  return Promise.all(fixture.map(item => layout(p, item)));
}

function initializeSync(p /*: string*/, fixture /*: Fixture*/) {
  fixture.forEach(item => layoutSync(p, item));
}

module.exports = {
  initialize,
  initializeSync,
  dir,
  file,
  symlink,
  json,
  packageJson,
};
