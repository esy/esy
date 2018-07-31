/**
 * Utilities for mocking npm registry.
 *
 * @flow
 */

import type {ServerResponse} from 'http';
import type {Gzip} from 'zlib';

const path = require('path');
const crypto = require('crypto');
const deepResolve = require('super-resolve');
const http = require('http');
const invariant = require('invariant');
const semver = require('semver');

const fsUtils = require('./fs');

export type PackageDesc = {|
  path: string,
  packageJson: Object,
  shasum?: string,
|};
export type PackageEntry = Map<string, PackageDesc>;
export type PackageRegistry = Map<string, PackageEntry>;

export type PackageRunDriver = (
  string,
  Array<string>,
  {registryUrl: string},
) => Promise<{|stdout: Buffer, stderr: Buffer|}>;

export type PackageDriver = any;

async function definePackage(
  packageJson: {name: string, version: string},
  options: {shasum?: string} = {},
) {
  const packageRegistry = await getPackageRegistry();
  const {name, version} = packageJson;
  invariant(name != null, 'Missing "name" in package.json');
  invariant(version != null, 'Missing "version" in package.json');

  let packageEntry = packageRegistry.get(name);

  if (!packageEntry) {
    packageRegistry.set(name, (packageEntry = new Map()));
  }

  const packagePath = await fsUtils.createTemporaryFolder();
  await fsUtils.writeJson(path.join(packagePath, 'package.json'), packageJson);
  packageEntry.set(version, {
    path: packagePath,
    packageJson,
    shasum: options.shasum,
  });
  return packagePath;
}

async function defineLocalPackage(
  packagePath: string,
  packageJson: {name: string, version: string},
) {
  const {name, version} = packageJson;
  invariant(name != null, 'Missing "name" in package.json');
  invariant(version != null, 'Missing "version" in package.json');

  await fsUtils.mkdir(packagePath);
  await fsUtils.writeJson(path.join(packagePath, 'package.json'), packageJson);
}

function getPackageRegistry(): Promise<PackageRegistry> {
  if ((getPackageRegistry: any).promise) {
    return (getPackageRegistry: any).promise;
  }

  return (getPackageRegistry.promise = (async () => {
    const packageRegistry = new Map();
    for (const packageFile of await fsUtils.walk(path.join(__dirname, '../fixtures'), {
      filter: ['package.json'],
    })) {
      const packageJson = await fsUtils.readJson(packageFile);
      const {name, version} = packageJson;

      if (name.startsWith('git-')) {
        continue;
      }

      let packageEntry = packageRegistry.get(name);

      if (!packageEntry) {
        packageRegistry.set(name, (packageEntry = new Map()));
      }

      packageEntry.set(version, {
        path: require('path').dirname(packageFile),
        packageJson,
      });
    }

    return packageRegistry;
  })());
}

function clearPackageRegistry() {
  delete getPackageRegistry.promise;
}

async function getPackageEntry(name: string): Promise<?PackageEntry> {
  const packageRegistry = await getPackageRegistry();

  return packageRegistry.get(name);
}

async function getPackageArchiveStream(name: string, version: string): Promise<Gzip> {
  const packageEntry = await getPackageEntry(name);

  if (!packageEntry) {
    throw new Error(`Unknown package "${name}"`);
  }

  const packageVersionEntry = packageEntry.get(version);

  if (!packageVersionEntry) {
    throw new Error(`Unknown version "${version}" for package "${name}"`);
  }

  return fsUtils.packToStream(packageVersionEntry.path, {
    virtualPath: '/package',
  });
}

async function getPackageArchivePath(name: string, version: string): Promise<string> {
  const packageEntry = await getPackageEntry(name);

  if (!packageEntry) {
    throw new Error(`Unknown package "${name}"`);
  }

  const packageVersionEntry = packageEntry.get(version);

  if (!packageVersionEntry) {
    throw new Error(`Unknown version "${version}" for package "${name}"`);
  }

  const archivePath = await fsUtils.createTemporaryFile(`${name}-${version}.tar.gz`);

  await fsUtils.packToFile(archivePath, packageVersionEntry.path, {
    virtualPath: '/package',
  });

  return archivePath;
}

async function getPackageArchiveHash(
  name: string,
  version: string,
): Promise<string | Buffer> {
  const stream = await getPackageArchiveStream(name, version);

  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha1');
    hash.setEncoding('hex');

    // Send the archive to the hash function
    stream.pipe(hash);

    stream.on('end', () => {
      const finalHash = hash.read();
      invariant(finalHash, 'The hash should have been computated');
      resolve(finalHash);
    });
  });
}

async function getPackageHttpArchivePath(name: string, version: string): Promise<string> {
  const packageEntry = await getPackageEntry(name);

  if (!packageEntry) {
    throw new Error(`Unknown package "${name}"`);
  }

  const packageVersionEntry = packageEntry.get(version);

  if (!packageVersionEntry) {
    throw new Error(`Unknown version "${version}" for package "${name}"`);
  }

  const serverUrl = await startPackageServer();
  const archiveUrl = `${serverUrl}/${name}/-/${name}-${version}.tgz`;

  return archiveUrl;
}

async function getPackageDirectoryPath(name: string, version: string): Promise<string> {
  const packageEntry = await getPackageEntry(name);

  if (!packageEntry) {
    throw new Error(`Unknown package "${name}"`);
  }

  const packageVersionEntry = packageEntry.get(version);

  if (!packageVersionEntry) {
    throw new Error(`Unknown version "${version}" for package "${name}"`);
  }

  return packageVersionEntry.path;
}

function startPackageServer(options: {persistent?: boolean} = {}): Promise<string> {
  if ((startPackageServer: any).url) {
    return (startPackageServer: any).url;
  }

  async function processPackageInfo(
    params: ?Array<string>,
    res: ServerResponse,
  ): Promise<boolean> {
    if (!params) {
      return false;
    }

    const [, scope, localName] = params;
    const name = scope ? `${scope}/${localName}` : localName;

    const packageEntry = await getPackageEntry(name);

    if (!packageEntry) {
      return processError(res, 404, `Package not found: ${name}`);
    }

    const versions = Array.from(packageEntry.keys());

    const data = JSON.stringify({
      name,
      versions: Object.assign(
        {},
        ...(await Promise.all(
          versions.map(async version => {
            const packageVersionEntry = packageEntry.get(version);
            invariant(packageVersionEntry, 'This can only exist');

            return {
              [version]: Object.assign({}, packageVersionEntry.packageJson, {
                dist: {
                  shasum:
                    packageVersionEntry.shasum ||
                    (await getPackageArchiveHash(name, version)),
                  tarball: await getPackageHttpArchivePath(name, version),
                },
              }),
            };
          }),
        )),
      ),
      ['dist-tags']: {latest: semver.maxSatisfying(versions, '*')},
    });

    res.writeHead(200, {['Content-Type']: 'application/json'});
    res.end(data);

    return true;
  }

  async function processPackageTarball(
    params: ?Array<string>,
    res: ServerResponse,
  ): Promise<boolean> {
    if (!params) {
      return false;
    }

    const [, scope, localName, version] = params;
    const name = scope ? `${scope}/${localName}` : localName;

    const packageEntry = await getPackageEntry(name);

    if (!packageEntry) {
      return processError(res, 404, `Package not found: ${name}`);
    }

    const packageVersionEntry = packageEntry.get(version);

    if (!packageVersionEntry) {
      return processError(res, 404, `Package not found: ${name}@${version}`);
    }

    res.writeHead(200, {
      ['Content-Type']: 'application/octet-stream',
      ['Transfer-Encoding']: 'chunked',
    });

    const packStream = fsUtils.packToStream(packageVersionEntry.path, {
      virtualPath: '/package',
    });
    packStream.pipe(res);

    return true;
  }

  function processError(
    res: ServerResponse,
    statusCode: number,
    errorMessage: string,
  ): boolean {
    console.error(errorMessage);

    res.writeHead(statusCode);
    res.end(errorMessage);

    return true;
  }

  return new Promise((resolve, reject) => {
    const server = http.createServer(
      (req, res) =>
        void (async () => {
          try {
            if (
              await processPackageInfo(
                req.url.match(/^\/(?:(@[^\/]+)\/)?([^@\/][^\/]*)$/),
                res,
              )
            ) {
              return;
            }

            if (
              await processPackageTarball(
                req.url.match(/^\/(?:(@[^\/]+)\/)?([^@\/][^\/]*)\/-\/\2-(.*)\.tgz$/),
                res,
              )
            ) {
              return;
            }

            processError(res, 404, `Invalid route: ${req.url}`);
          } catch (error) {
            processError(res, 500, error.stack);
          }
        })(),
    );

    if (!options.persistent) {
      // We don't want the server to prevent the process from exiting
      server.unref();
    }
    server.listen(() => {
      const {port} = server.address();
      resolve((startPackageServer.url = `http://localhost:${port}`));
    });
  });
}

function generatePkgDriver({runDriver}: {|runDriver: PackageRunDriver|}): PackageDriver {
  function withConfig(definition): PackageDriver {
    const makeTemporaryEnv = (packageJson, subDefinition, fn) => {
      if (typeof subDefinition === 'function') {
        fn = subDefinition;
        subDefinition = {};
      }

      if (typeof fn !== 'function') {
        throw new Error(
          // eslint-disable-next-line
          `Invalid test function (got ${typeof fn}) - you probably put the closing parenthesis of the "makeTemporaryEnv" utility at the wrong place`,
        );
      }

      return async function(): Promise<void> {
        const path = await fsUtils.createTemporaryFolder();

        const registryUrl = await startPackageServer();

        // Writes a new package.json file into our temporary directory
        await fsUtils.writeJson(`${path}/package.json`, await deepResolve(packageJson));

        const run = (...args) => {
          return runDriver(path, args, {
            registryUrl,
            ...subDefinition,
          });
        };

        const source = async script => {
          return JSON.parse(
            (await run('node', '-p', `JSON.stringify(${script})`)).stdout.toString(),
          );
        };

        await fn({
          path,
          run,
          source,
        });
      };
    };

    makeTemporaryEnv.withConfig = subDefinition => {
      return withConfig({...definition, ...subDefinition});
    };

    return makeTemporaryEnv;
  }

  return withConfig({});
}

type Layout = {
  name: string,
  version: string,
  path: string,
  dependencies: {[name: string]: Layout},
};

async function crawlLayout(directory: string): Promise<?Layout> {
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
        const dep = await crawlLayout(depDirectory);
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

module.exports = {
  getPackageDirectoryPath,
  getPackageHttpArchivePath,
  getPackageArchivePath,
  definePackage,
  defineLocalPackage,
  generatePkgDriver,
  crawlLayout,
  clearPackageRegistry,
  startPackageServer,
  getPackageRegistry,
};
