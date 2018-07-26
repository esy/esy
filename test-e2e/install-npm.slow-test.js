// @flow

const child_process = require('child_process');
const fs = require('fs');
const path = require('path');
const rmSync = require('rimraf').sync;
const {genFixture} = require('./test/helpers.js');

const cases = [
  {
    name: "react",
    test: `
      require('react');
    `
  },
  {
    name: "bs-platform"
  },
  {
    name: "browserify",
    test: `
      require('browserify');
    `
  },
  {
    name: "webpack",
    test: `
      require('webpack');
    `
  },
  {
    name: "jest-cli",
    test: `
      require('jest-cli');
    `
  },
  {
    name: "flow-bin",
    test: `
      require('flow-bin');
    `
  },
  {
    name: "babel-cli",
    test: `
      require('babel-core');
    `
  },
];



describe('Install npm packages', function() {

  let p;
  let reposUpdated = false;

  beforeAll(async () => {
    p = await genFixture();
  });

  for (let c of cases) {

    it(`installing ${c.name}`, () => {

      const sandboxPath = path.join(p.projectPath, c.name);
      fs.mkdirSync(sandboxPath);

      const esy = path.join(p.binPath, 'esy');

      const packageJson = {
        name: `test-${c.name}`,
        version: '0.0.0',
        esy: {build: ['true']},
        dependencies: {
          [c.name]: "*"
        }
      };

      fs.writeFileSync(
        path.join(sandboxPath, 'package.json'),
        JSON.stringify(packageJson, null, 2)
      );

      child_process.execSync(`${esy} install`, {
        cwd: sandboxPath,
        env: {...process.env, ESY__PREFIX: p.esyPrefixPath},
        stdio: 'inherit',
      });

      child_process.execSync(`${esy} build`, {
        cwd: sandboxPath,
        env: {...process.env, ESY__PREFIX: p.esyPrefixPath},
        stdio: 'inherit',
      });

      if (c.test != null) {
        const test = c.test;
        fs.writeFileSync(
          path.join(sandboxPath, 'test.js'),
          test
        );
        child_process.execSync(`node ./test.js`, {
          cwd: sandboxPath,
          stdio: 'inherit',
        });
      }

      rmSync(sandboxPath);
    });
  }

});
