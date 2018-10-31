// @flow

const path = require('path');
const fs = require('../test/fs.js');
const helpers = require('../test/helpers.js');

const {file, packageJson} = helpers;

helpers.skipSuiteOnWindows();

describe('projects with multiple sandboxes', function() {
  it('run installs different deps dependening on a sandbox config', async () => {
    const fixture = [
      file(
        'package.json',
        `
        {
          "esy": {},
          "dependencies": {"default-dep": "*"}
        }
        `,
      ),
      file(
        'package.custom.json',
        `
        {
          "esy": {},
          "dependencies": {"custom-dep": "*"}
        }
        `,
      ),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    p.defineNpmPackage({
      name: 'default-dep',
      version: '0.0.0',
      esy: {},
    });
    p.defineNpmPackage({
      name: 'custom-dep',
      version: '0.0.0',
      esy: {},
    });

    // install default sandbox

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath, 'default')).toMatchObject({
      dependencies: {
        'default-dep': {name: 'default-dep', version: '0.0.0'},
      },
    });
    expect(await fs.exists(path.join(p.projectPath, 'esy.lock'))).toBeTruthy();

    // install custom sandbox

    await p.esy('@package.custom.json install');

    expect(
      await helpers.readInstalledPackages(p.projectPath, 'package.custom'),
    ).toMatchObject({
      dependencies: {
        'custom-dep': {name: 'custom-dep', version: '0.0.0'},
      },
    });
    expect(
      await fs.exists(path.join(p.projectPath, 'package.custom.esy.lock')),
    ).toBeTruthy();
  });
});
