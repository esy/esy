/* @flow */

const setup = require('./setup');

describe(`Tests for installations from custom sources`, () => {
  describe('Installation from github', () => {
    beforeEach(async () => {
      await setup.definePackage({
        name: 'lodash',
        version: '4.24.0',
      });
    });

    async function assertLayoutCorrect(path) {
      await expect(setup.crawlLayout(path)).resolves.toMatchObject({
        dependencies: {
          'example-yarn-package': {
            name: 'example-yarn-package',
            version: '1.0.0',
          },
          lodash: {
            name: 'lodash',
            version: '4.24.0',
          },
        },
      });
    }

    test(
      'it should install without ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package`},
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'it should install with branch as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package#master`},
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'it should install with 6 char commit sha as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43`},
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'it should install with 9 char commit sha as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43f77`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'it should install with 40 char commit sha as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43f77361ff7739bcb42de7787b09208bcece`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );
  });

  describe('Installation from git', () => {
    beforeEach(async () => {
      await setup.definePackage({
        name: 'lodash',
        version: '4.24.0',
      });
    });

    async function assertLayoutCorrect(path) {
      await expect(setup.crawlLayout(path)).resolves.toMatchObject({
        dependencies: {
          'example-yarn-package': {
            name: 'example-yarn-package',
            version: '1.0.0',
          },
          lodash: {
            name: 'lodash',
            version: '4.24.0',
          },
        },
      });
    }

    test(
      'install from git+https:// with no ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'install from git+https:// with branch as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git#master`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'install from git+https:// with commit sha as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git#0b8f43`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'install from git:// with no ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'install from git:// with branch as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git#master`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );

    test(
      'install from git:// with commit as ref',
      setup.makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git#0b8f43`,
          },
        },
        async ({path, run, source}) => {
          await run('install');
          await assertLayoutCorrect(path);
        },
      ),
    );
  });
});
