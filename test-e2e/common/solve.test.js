const path = require('path');
const fs = require('fs-extra');
const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {packageJson, file, dir} = helpers;
const {version} = require('../../package.json');

helpers.skipSuiteOnWindows('needs fixes for path pretty printing');

async function createSandbox(config) {
  const p = await helpers.createTestSandbox();

  await p.defineNpmPackage({
    name: '@esy-ocaml/substs',
    version: '1.0.0',
    esy: {},
  });

  let opamTemplate = {
    opam: outdent`
        opam-version: "2.0"
      `,
    url: null,
  };
  for (let i = 0, l = (config.opam || []).length; i < l; i++) {
    await p.defineOpamPackage({...opamTemplate, ...config.opam[i]});
  }

  let npmTemplate = {esy: {}};
  for (let i = 0, l = (config.npm || []).length; i < l; i++) {
    await p.defineNpmPackage({...npmTemplate, ...config.npm[i]});
  }

  await p.fixture(
    packageJson({
      name: 'root',
      version: '1.0.0',
      esy: {},
      ...config.root,
    }),
  );

  return Promise.resolve(p);
}

describe('Dumps CUDF', function() {
  it('...to stdout', async () => {
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
      'solve --dump-cudf-request=- --dump-cudf-solution=- --skip-repository-update',
    );
    expect(res.stdout.trim()).toMatchSnapshot();
  });

  it('...to files on disk', async () => {
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
      'solve --dump-cudf-request=cudf.in --dump-cudf-solution=cudf.out --skip-repository-update',
    );

    const cudfIn = fs
      .readFileSync(path.join(p.projectPath, 'cudf.in'))
      .toString()
      .trim();
    expect(cudfIn).toMatchSnapshot();

    const cudfOut = fs
      .readFileSync(path.join(p.projectPath, 'cudf.out'))
      .toString()
      .trim();
    expect(cudfOut).toMatchSnapshot();
  });
});

describe('NPM depends on OPAM', function() {
  it('"<3" for: 1, 2', async () => {
    const p = await createSandbox({
      opam: [{name: 'pkg', version: '1.0.0'}, {name: 'pkg', version: '2.0.0'}],
      root: {
        dependencies: {
          '@opam/pkg': '<3.0.0',
        },
      },
    });

    const res = await p.esy('solve --dump-cudf-request=- --skip-repository-update');
    expect(res.stdout.trim()).toMatchSnapshot();
    // console.log(res.stdout.trim())
  });

  it('"<2" for: 1, 2', async () => {
    const p = await createSandbox({
      opam: [{name: 'pkg', version: '1.0.0'}, {name: 'pkg', version: '1.5.0'}],
      root: {
        dependencies: {
          '@opam/pkg': '<1.5.0',
        },
      },
    });

    const res = await p.esy('solve --dump-cudf-request=- --skip-repository-update');
    expect(res.stdout.trim()).toMatchSnapshot();
  });

  it('"1 - 3 || 6 - 9" for 1 - 10', async () => {
    const p = await createSandbox({
      opam: [
        {name: 'pkg', version: '1.0.0'},
        {name: 'pkg', version: '2.0.0'},
        {name: 'pkg', version: '3.0.0'},
        {name: 'pkg', version: '4.0.0'},
        {name: 'pkg', version: '5.0.0'},
        {name: 'pkg', version: '6.0.0'},
        {name: 'pkg', version: '7.0.0'},
        {name: 'pkg', version: '8.0.0'},
        {name: 'pkg', version: '9.0.0'},
        {name: 'pkg', version: '10.0.0'},
      ],
      root: {
        dependencies: {
          '@opam/pkg': '>=1.0.0 <=3.0.0 || >5.0.0 <10.0.0',
        },
      },
    });

    const res = await p.esy('solve --dump-cudf-request=- --skip-repository-update');
    expect(res.stdout.trim()).toMatchSnapshot();
  });
});

describe('NPM depends on NPM', function() {
  it('"1 - 3 || 6 - 9" for 1 - 10', async () => {
    const p = await createSandbox({
      npm: [
        {name: 'pkg', version: '1.0.0'},
        {name: 'pkg', version: '2.0.0'},
        {name: 'pkg', version: '3.0.0'},
        {name: 'pkg', version: '4.0.0'},
        {name: 'pkg', version: '5.0.0'},
        {name: 'pkg', version: '6.0.0'},
        {name: 'pkg', version: '7.0.0'},
        {name: 'pkg', version: '8.0.0'},
        {name: 'pkg', version: '9.0.0'},
        {name: 'pkg', version: '10.0.0'},
      ],
      root: {
        dependencies: {
          pkg: '1.0.0 - 3.0.0 || >5.0.0 <10.0.0',
        },
      },
    });

    const res = await p.esy('solve --dump-cudf-request=- --skip-repository-update');
    expect(res.stdout.trim()).toMatchSnapshot();
  });
});

describe('OPAM depends on OPAM', function() {
  it('2 - 8 for 1 - 10', async () => {
    const p = await createSandbox({
      opam: [
        {name: 'pkg', version: '1.0.0'},
        {name: 'pkg', version: '2.0.0'},
        {name: 'pkg', version: '3.0.0'},
        {name: 'pkg', version: '4.0.0'},
        {name: 'pkg', version: '5.0.0'},
        {name: 'pkg', version: '6.0.0'},
        {name: 'pkg', version: '7.0.0'},
        {name: 'pkg', version: '8.0.0'},
        {name: 'pkg', version: '9.0.0'},
        {name: 'pkg', version: '10.0.0'},
        {
          name: 'x',
          version: '1.0.0',
          opam: outdent`
        opam-version: "2.0"
        depends: ["pkg" { >= "2.0" & <= "8.0"}]
      `,
        },
      ],
      root: {
        dependencies: {
          '@opam/x': '*',
        },
      },
    });

    const res = await p.esy('solve --dump-cudf-request=- --skip-repository-update');
    expect(res.stdout.trim()).toMatchSnapshot();
  });
});
