/**
 * Utilities for mocking opam registry.
 *
 * @flow
 */

import type {ServerResponse} from 'http';
import type {Fixture} from './FixtureUtils.js';

const outdent = require('outdent');
const crypto = require('crypto');
const http = require('http');
const path = require('path');
const fs = require('fs-extra');
const {createTemporaryFolder, packToFile} = require('./fs.js');
const FixtureUtils = require('./FixtureUtils.js');

export type OpamRegistry = {
  registryPath: string,
  overridePath: string,
  serverUrl: string,
  packageSourcesPath: string,
};

async function initialize(): Promise<OpamRegistry> {
  const registryPath = await createTemporaryFolder();
  await fs.mkdirp(path.join(registryPath, 'packages'));
  await fs.writeFile(
    path.join(registryPath, 'repo'),
    outdent`
      opam-version: "1.2"
      browse: "https://opam.ocaml.org/pkg/"
      upstream: "https://github.com/ocaml/opam-repository/tree/master/"
    `,
  );

  const overridePath = await createTemporaryFolder();
  await fs.mkdirp(path.join(overridePath, 'packages'));

  const packageSourcesPath = await createTemporaryFolder();

  const serverUrl = await new Promise((resolve, reject) => {
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

    async function processPackageTarball(
      tarballName: string,
      res: ServerResponse,
    ): Promise<boolean> {
      const tarballPath = path.join(packageSourcesPath, tarballName);
      if (!(await fs.exists(tarballPath))) {
        return processError(res, 404, `Tarball not found: ${tarballPath}`);
      }

      res.writeHead(200, {
        ['Content-Type']: 'application/octet-stream',
        ['Transfer-Encoding']: 'chunked',
      });

      const out = fs.createReadStream(tarballPath);
      out.pipe(res);

      return true;
    }

    const server = http.createServer(
      (req, res) =>
        void (async () => {
          try {
            const url = req.url;
            if (await processPackageTarball(url, res)) {
              return;
            }

            processError(res, 404, `Invalid route: ${url}`);
          } catch (error) {
            processError(res, 500, error.stack);
          }
        })(),
    );
    server.listen(() => {
      server.unref();
      const {port} = server.address();
      resolve(`http://localhost:${port}`);
    });
  });

  return {serverUrl, registryPath, overridePath, packageSourcesPath};
}

async function defineOpamPackage(
  registry: OpamRegistry,
  spec: {
    name: string,
    version: string,
    opam: string,
    url: ?string,
  },
) {
  const packagePath = path.join(registry.registryPath, 'packages', spec.name);
  await fs.mkdirp(packagePath);

  const packageVersionPath = path.join(packagePath, `${spec.name}.${spec.version}`);
  await fs.mkdirp(packageVersionPath);

  await fs.writeFile(path.join(packageVersionPath, 'opam'), spec.opam);
  if (spec.url != null) {
    await fs.writeFile(path.join(packageVersionPath, 'url'), spec.url);
  }
}

async function defineOpamPackageOfExtraSource(
  registry: OpamRegistry,
  spec: {
    name: string,
    version: string,
    opam: string,
    url: ?string,
  },
) {
  await defineOpamPackage(registry, spec);

  const packagePath = path.join(registry.registryPath, 'packages', spec.name);
  await fs.mkdirp(packagePath);

  const packageVersionPath = path.join(packagePath, `${spec.name}.${spec.version}`);
  await fs.mkdirp(packageVersionPath);

  const tarballFilename = `${spec.name}@${spec.version}.tgz`;

  const packageSourcePath = await createTemporaryFolder();

  const tarballPath = path.join(registry.packageSourcesPath, tarballFilename);
  await packToFile(tarballPath, packageSourcePath, {
    virtualPath: `/${spec.name}-${spec.version}`,
  });

  const data = await fs.readFile(tarballPath);
  const hasher = crypto.createHash('md5');
  hasher.update(data);
  const checksum = hasher.digest('hex');

  await fs.writeFile(
    path.join(packageVersionPath, 'opam'),
    outdent`
      ${spec.opam}
      install: [
        [
          "sh"
          "-c"
          "(mkdir -p %{lib}%/${spec.name} && tar xf ${tarballFilename})"
        ]
      ]
      extra-source "${tarballFilename}" {
        src: "${registry.serverUrl}/${tarballFilename}"
        checksum: "md5=${checksum}"
      }
    `,
  );
}

async function defineOpamPackageOfFixture(
  registry: OpamRegistry,
  spec: {
    name: string,
    version: string,
    opam: string,
  },
  fixture: Fixture,
) {
  const packagePath = path.join(registry.registryPath, 'packages', spec.name);
  await fs.mkdirp(packagePath);

  const packageVersionPath = path.join(packagePath, `${spec.name}.${spec.version}`);
  await fs.mkdirp(packageVersionPath);

  const tarballFilename = `${spec.name}@${spec.version}.tgz`;
  await fs.writeFile(path.join(packageVersionPath, 'opam'), spec.opam);
  const packageSourcePath = await createTemporaryFolder();
  await FixtureUtils.initialize(packageSourcePath, fixture);

  const tarballPath = path.join(registry.packageSourcesPath, tarballFilename);
  await packToFile(tarballPath, packageSourcePath, {
    virtualPath: `/${spec.name}-${spec.version}`,
  });

  const data = await fs.readFile(tarballPath);
  const hasher = crypto.createHash('md5');
  hasher.update(data);
  const checksum = hasher.digest('hex');

  await fs.writeFile(
    path.join(packageVersionPath, 'url'),
    outdent`
      archive: "${registry.serverUrl}/${tarballFilename}"
      checksum: "${checksum}"
    `,
  );
}

module.exports = {
  initialize,
  defineOpamPackage,
  defineOpamPackageOfFixture,
  defineOpamPackageOfExtraSource,
};
