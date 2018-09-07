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

async function crawlDependencies(nodeModulesPath) {
  const dependencies = {};

  if (await fsUtils.exists(nodeModulesPath)) {
    const items = await fsUtils.readdir(nodeModulesPath);
    await Promise.all(
      items.map(async name => {
        if (name[0] === '@') {
          const scopedNodeModulesPath = path.join(nodeModulesPath, name);
          const items = await fsUtils.readdir(scopedNodeModulesPath);
          for (const name of items) {
            const depDirectory = path.join(scopedNodeModulesPath, name);
            const dep = await crawlPackage(depDirectory);
            if (dep != null) {
              dependencies[dep.name] = dep;
            }
          }
        } else {
          const depDirectory = path.join(nodeModulesPath, name);
          const dep = await crawlPackage(depDirectory);
          if (dep != null) {
            dependencies[dep.name] = dep;
          }
        }
      }),
    );
  }
  return dependencies;
}

async function crawlPackage(
  directory: string,
  nodeModulesPath?: string,
): Promise<?Package> {
  const esyLinkPath = path.join(directory, '_esylink');
  if (nodeModulesPath == null) {
    nodeModulesPath = path.join(directory, 'node_modules');
  }

  let packageJsonPath;
  let opamPath;
  if (await fsUtils.exists(esyLinkPath)) {
    let link = JSON.parse(await fsUtils.readFile(esyLinkPath, 'utf8'));
    let sourcePath = link.path;
    packageJsonPath = path.join(sourcePath, 'package.json');
    opamPath = path.join(sourcePath, '_esy', 'opam');
  } else {
    packageJsonPath = path.join(directory, 'package.json');
    opamPath = path.join(directory, '_esy', 'opam');
  }

  if (await fsUtils.exists(packageJsonPath)) {
    const packageJson = await fsUtils.readJson(packageJsonPath);
    const dependencies = await crawlDependencies(nodeModulesPath);
    return {
      name: packageJson.name,
      version: packageJson.version,
      path: directory,
      dependencies,
    };
  } else if (await fsUtils.exists(opamPath)) {
    const dependencies = await crawlDependencies(nodeModulesPath);
    return {
      name: path.basename(directory),
      version: 'opam',
      path: directory,
      dependencies,
    };
  } else {
    return null;
  }
}

function crawl(directory: string, sandbox?: string = 'default') {
  return crawlPackage(directory, path.join(directory, '_esy', sandbox, 'node_modules'));
}

module.exports = {crawl};
