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

function parseId(id) {
  if (id[0] === '@') {
    const [_, name, version] = id.split('@');
    return {name: '@' + name, version};
  } else {
    const [name, version] = id.split('@');
    return {name: name, version};
  }
}

async function crawlDependencies(root, nodeModulesPath) {
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
            const dep = await crawlPackage(root, depDirectory);
            if (dep != null) {
              dependencies[dep.name] = dep;
            }
          }
        } else {
          const depDirectory = path.join(nodeModulesPath, name);
          const dep = await crawlPackage(root, depDirectory);
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
  root,
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
    let parseSource = /link:(.+)/;
    let m = parseSource.exec(link.source);
    if (m != null) {
      let sourcePath = m[1];
      packageJsonPath = path.join(root, sourcePath, 'package.json');
      opamPath = path.join(root, sourcePath, '_esy', 'opam');
    } else {
      packageJsonPath = path.join(directory, 'package.json');
      opamPath = path.join(directory, '_esy', 'opam');
    }
  } else {
    packageJsonPath = path.join(directory, 'package.json');
    opamPath = path.join(directory, '_esy', 'opam');
  }

  if (await fsUtils.exists(packageJsonPath)) {
    const packageJson = await fsUtils.readJson(packageJsonPath);
    const dependencies = await crawlDependencies(root, nodeModulesPath);
    return {
      name: packageJson.name,
      version: packageJson.version,
      path: directory,
      dependencies,
    };
  } else if (await fsUtils.exists(opamPath)) {
    const dependencies = await crawlDependencies(root, nodeModulesPath);
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
  return crawlPackage(
    directory,
    directory,
    path.join(directory, '_esy', sandbox, 'node_modules'),
  );
}

type InstallationItem = {
  type: 'link' | 'install',
  path: string,
  source: string,
};

type Installation = {
  [id: string]: InstallationItem,
};

type SolutionItem = {
  name: string,
  version: string,
  dependencies: string[],
  devDependencies: string[],
};

type Solution = {
  hash: string,
  root: string,
  node: {
    [id: string]: SolutionItem,
  },
};

async function readSolution(
  projectPath: string,
  sandbox?: string = 'default',
): Promise<?Solution> {
  let solutionPath;
  if (sandbox === 'default') {
    solutionPath = path.join(projectPath, 'esy.lock', 'index.json');
  } else {
    solutionPath = path.join(projectPath, `${sandbox}.esy.lock`, 'index.json');
  }

  if (!(await fsUtils.exists(solutionPath))) {
    return null;
  }
  const data = await fsUtils.readFile(solutionPath, 'utf8');
  const solution: Solution = JSON.parse(data);
  return solution;
}

async function readInstallation(
  projectPath: string,
  sandbox?: string = 'default',
): Promise<?Installation> {
  const installationPath = path.join(projectPath, '_esy', sandbox, 'installation.json');

  if (!(await fsUtils.exists(installationPath))) {
    return null;
  }

  const data = await fsUtils.readFile(installationPath, 'utf8');
  const installation: Installation = JSON.parse(data);
  return installation;
}

async function read(directory: string, sandbox?: string = 'default'): Promise<?Package> {
  const installation = await readInstallation(directory, sandbox);
  const solution = await readSolution(directory, sandbox);
  if (solution == null) {
    throw new Error('no solution found');
  }
  if (installation == null) {
    throw new Error('no installation found');
  }

  function make(id) {
    const item = solution.node[id];

    const dependencies = {};
    for (const dep of item.dependencies) {
      const {name} = parseId(dep);
      dependencies[name] = make(dep);
    }

    for (const dep of item.devDependencies) {
      const {name} = parseId(dep);
      dependencies[name] = make(dep);
    }

    return {
      name: item.name,
      version: item.version,
      path: installation[id].path,
      dependencies,
    };
  }

  return make(solution.root);
}

module.exports = {crawl, read};
