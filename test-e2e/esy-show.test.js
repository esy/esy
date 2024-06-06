// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('./test/helpers');
const fixture = require('./common/fixture.js');

describe('esy show', () => {
  it('shows info about packages hosted on npm', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(helpers.packageJson({}));
    await p.defineNpmPackage({
      name: 'react',
      version: '1.0.0',
    });
    await p.defineNpmPackage({
      name: 'react',
      version: '2.0.0',
    });

    {
      const {stdout} = await p.esy('show react');
      expect(JSON.parse(stdout)).toEqual({
        name: 'react',
        versions: ['2.0.0', '1.0.0'],
      });
    }

    {
      const {stdout} = await p.esy('show react@1.0.0');
      expect(JSON.parse(stdout)).toEqual({
        name: 'react',
        version: '1.0.0',
        dependencies: [],
        devDependencies: [],
        peerDependencies: [],
        optDependencies: [],
      });
    }
  });

  it('shows info about packages hosted on opam', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(helpers.packageJson({}));
    await p.defineOpamPackage({
      name: 'bos',
      version: '1.0.0',
      opam: `opam-version: "2.0"`,
      url: null,
    });
    await p.defineOpamPackage({
      name: 'bos',
      version: '2.0.0',
      opam: `opam-version: "2.0"`,
      url: null,
    });

    {
      const {stdout} = await p.esy('show @opam/bos');
      expect(JSON.parse(stdout)).toEqual({
        name: '@opam/bos',
        versions: ['2.0.0', '1.0.0'],
      });
    }

    {
      const {stdout} = await p.esy('show @opam/bos@2.0.0');
      expect(JSON.parse(stdout)).toEqual({
        dependencies: [[{'@esy-ocaml/substs': '*'}]],
        devDependencies: [],
        name: '@opam/bos',
        optDependencies: [],
        peerDependencies: [],
        version: '2.0.0',
      });
    }
  });

  it('shows info about packages hosted on github', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(helpers.packageJson({}));

    {
      const {stdout} = await p.esy(
        'show example-yarn-package@yarnpkg/example-yarn-package',
      );
      expect(JSON.parse(stdout)).toEqual({
        dependencies: [[{lodash: '^4.16.2'}]],
        devDependencies: [[{'jest-cli': '=15.1.1'}]],
        name: 'example-yarn-package',
        optDependencies: [],
        peerDependencies: [],
        version:
          'github:yarnpkg/example-yarn-package#0b8f43f77361ff7739bcb42de7787b09208bcece',
      });
    }
  });
});
