// @flow

const path = require('path');
const helpers = require('./test/helpers.js');

describe(`'esy status' command`, function() {
  it('can be run outside of esy project', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture();

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toEqual({
      isProject: false,
      isProjectFetched: false,
      isProjectReadyForDev: false,
      isProjectSolved: false,
      rootBuildPath: null,
      rootInstallPath: null,
      rootPackageConfigPath: null,
    });
  });

  const fixture = [
    helpers.packageJson({
      name: 'root',
      dependencies: {
        dep: 'path:./dep',
      },
    }),
    helpers.file(
      'dev.json',
      JSON.stringify(
        {
          name: 'dev',
          dependencies: {
            dep: 'path:./dep',
          },
        },
        null,
        2,
      ),
    ),
    helpers.dir(
      'dep',
      helpers.packageJson({
        name: 'dep',
        esy: {},
      }),
    ),
  ];

  it('can be run inside project, not solved', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture);

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toEqual({
      isProject: true,
      isProjectFetched: false,
      isProjectReadyForDev: false,
      isProjectSolved: false,
      rootBuildPath: null,
      rootInstallPath: null,
      rootPackageConfigPath: path.join(p.projectPath, 'package.json'),
    });
  });

  it('can be run inside project, not fetched', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture);
    await p.esy('solve');

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toEqual({
      isProject: true,
      isProjectFetched: false,
      isProjectReadyForDev: false,
      isProjectSolved: true,
      rootBuildPath: null,
      rootInstallPath: null,
      rootPackageConfigPath: path.join(p.projectPath, 'package.json'),
    });
  });

  it('can be run inside project, not ready', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture);
    await p.esy('install');

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toMatchObject({
      isProject: true,
      isProjectFetched: true,
      isProjectReadyForDev: false,
      isProjectSolved: true,
      rootPackageConfigPath: path.join(p.projectPath, 'package.json'),
    });
    expect(status.rootBuildPath).not.toBe(null);
    expect(status.rootInstallPath).not.toBe(null);
  });

  it('can be run inside project, ready', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture);
    await p.esy('install');
    await p.esy('build');

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toMatchObject({
      isProject: true,
      isProjectFetched: true,
      isProjectReadyForDev: true,
      isProjectSolved: true,
      rootPackageConfigPath: path.join(p.projectPath, 'package.json'),
    });
    expect(status.rootBuildPath).not.toBe(null);
    expect(status.rootInstallPath).not.toBe(null);
  });

  it('reports correct "rootPackageConfigPath" with named invocation', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture);
    await p.esy('@dev install');
    await p.esy('@dev build');

    const {stdout} = await p.esy('@dev status --json');
    const status = JSON.parse(stdout);
    expect(status).toMatchObject({
      isProject: true,
      isProjectFetched: true,
      isProjectReadyForDev: true,
      isProjectSolved: true,
      rootPackageConfigPath: path.join(p.projectPath, 'dev.json'),
    });
    expect(status.rootBuildPath).not.toBe(null);
    expect(status.rootInstallPath).not.toBe(null);
  });
});
