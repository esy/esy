// @flow

const path = require('path');

const outdent = require('outdent');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows('Needs investigation');

function makeFixture(p) {
  return [
    helpers.packageJson({
      name: 'with-linked-dep-sandbox-env',
      version: '1.0.0',
      esy: {
        build: 'true',
        sandboxEnv: {
          SANDBOX_ENV_VAR: 'global-sandbox-env-var',
        },
      },
      dependencies: {
        dep: '*',
      },
      buildTimeDependencies: {
        buildTimDep: '*',
      },
      devDependencies: {
        devDep: '*',
      },
    }),
    helpers.dir(
      'node_modules',
      helpers.dir(
        'dep',
        helpers.symlink('package.json', path.join('..', '..', 'dep')),
        helpers.file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'dep')}`}),
        ),
      ),
      helpers.dir(
        'buildTimDep',
        helpers.symlink('package.json', path.join('..', '..', 'buildTimDep')),
        helpers.file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'buildTimDep')}`}),
        ),
      ),
      helpers.dir(
        'devDep',
        helpers.symlink('package.json', path.join('..', '..', 'devDep')),
        helpers.file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'devDep')}`}),
        ),
      ),
    ),
    helpers.dir(
      'dep',
      helpers.packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          build: [
            'cp #{self.name}.js #{self.bin / self.name}.js',
            helpers.buildCommand('#{self.bin / self.name}.js'),
          ],
        },
      }),
      helpers.file(
        'dep.js',
        outdent`
          console.log(process.env.SANDBOX_ENV_VAR + "-in-dep");
        `,
      ),
    ),
    helpers.dir(
      'buildTimDep',
      helpers.packageJson({
        name: 'buildTimDep',
        version: '1.0.0',
        esy: {
          build: [
            'cp #{self.name}.js #{self.bin / self.name}.js',
            helpers.buildCommand('#{self.bin / self.name}.js'),
          ],
        },
      }),
      helpers.file(
        'buildTimDep.js',
        outdent`
          console.log(process.env.SANDBOX_ENV_VAR + "-in-buildTimDep");
        `,
      ),
    ),
    helpers.dir(
      'devDep',
      helpers.packageJson({
        name: 'devDep',
        version: '1.0.0',
        license: 'MIT',
        esy: {
          build: [
            'cp #{self.name}.js #{self.bin / self.name}.js',
            helpers.buildCommand('#{self.bin / self.name}.js'),
          ],
        },
      }),
      helpers.file(
        'devDep.js',
        outdent`
          console.log(process.env.SANDBOX_ENV_VAR + "-in-devDep");
        `,
      ),
    ),
  ];
}

describe('Linked deps with presence of sandboxEnv', () => {
  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('build');
    return p;
  }

  it("sandbox env should be visible in runtime dep's all envs", async () => {
    const p = await createTestSandbox();
    const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');

    const dep = await p.esy('dep.cmd');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep.cmd');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep.cmd');
    expect(x.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in build time dep's envs", async () => {
    const p = await createTestSandbox();
    const expecting = expect.stringMatching('-in-buildTimDep');

    const dep = await p.esy('buildTimDep.cmd');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b buildTimDep.cmd');
    expect(b.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in dev dep's envs", async () => {
    const p = await createTestSandbox();
    const dep = await p.esy('devDep.cmd');
    expect(dep.stdout).toEqual(expect.stringMatching('-in-devDep'));
  });
});
