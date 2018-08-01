/**
 * Represent node_modules directory in memory and make assertions against it.
 *
 * @flow
 */

const path = require('path');
const fsUtils = require('./fs');

export type Package = {
  name: string,
  version: string,
  path: string,
  dependencies: {[name: string]: Package},
};

async function crawl(directory: string): Promise<?Package> {
  const esyLinkPath = path.join(directory, '_esylink');
  const nodeModulesPath = path.join(directory, 'node_modules');

  let packageJsonPath;
  if (await fsUtils.exists(esyLinkPath)) {
    let sourcePath = await fsUtils.readFile(esyLinkPath, 'utf8');
    sourcePath = sourcePath.trim();
    packageJsonPath = path.join(sourcePath, 'package.json');
  } else {
    packageJsonPath = path.join(directory, 'package.json');
  }

  if (!(await fsUtils.exists(packageJsonPath))) {
    return null;
  }
  const packageJson = await fsUtils.readJson(packageJsonPath);
  const dependencies = {};

  if (await fsUtils.exists(nodeModulesPath)) {
    const items = await fsUtils.readdir(nodeModulesPath);
    await Promise.all(
      items.map(async name => {
        const depDirectory = path.join(directory, 'node_modules', name);
        const dep = await crawl(depDirectory);
        if (dep != null) {
          dependencies[dep.name] = dep;
        }
      }),
    );
  }

  return {
    name: packageJson.name,
    version: packageJson.version,
    path: directory,
    dependencies,
  };
}

module.exports = {crawl};
