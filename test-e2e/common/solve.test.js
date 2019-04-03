const path = require('path');
const fs = require('fs-extra');
const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {packageJson, file, dir} = helpers;
const {version} = require('../../package.json');

helpers.skipSuiteOnWindows('needs fixes for path pretty printing');

describe('esy solve', function() {
  it('dumps CUDF input & output to stdout', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      }),
    );

    const res = await p.esy(
      'solve --dump-cudf-input=- --dump-cudf-output=- --skip-repository-update',
    );
    expect(res.stdout.trim()).toEqual(outdent`
    preamble: 
    property: staleness: int, original-version: string

    package: root
    version: 1
    conflicts: root
    staleness: 0
    original-version: 0.0.0

    request: 
    install: root = 1
    preamble: 
    property: staleness: int, original-version: string

    package: root
    version: 1
    conflicts: root
    installed: true
    original-version: 0.0.0
    staleness: 0
    `);
  });

  it('dumps CUDF input & output to files on disk', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      }),
    );

    const res = await p.esy(
      'solve --dump-cudf-input=cudf.in --dump-cudf-output=cudf.out --skip-repository-update',
    );

    const cudfIn = fs
      .readFileSync(path.join(p.projectPath, 'cudf.in'))
      .toString()
      .trim();
    expect(cudfIn).toEqual(outdent`
    preamble: 
    property: staleness: int, original-version: string

    package: root
    version: 1
    conflicts: root
    staleness: 0
    original-version: 0.0.0

    request: 
    install: root = 1
    `);

    const cudfOut = fs
      .readFileSync(path.join(p.projectPath, 'cudf.out'))
      .toString()
      .trim();
    expect(cudfOut).toEqual(outdent`
    preamble: 
    property: staleness: int, original-version: string

    package: root
    version: 1
    conflicts: root
    installed: true
    original-version: 0.0.0
    staleness: 0
    `);
  });
});
