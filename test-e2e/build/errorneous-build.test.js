// @flow
const path = require('path');

const {createTestSandbox, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'errorneous-build',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      build: ['false'],
    },
  }),
];

it('Build - errorneous build', async () => {
  const p = await createTestSandbox(...fixture);
  try {
    await p.esy('build');
  } catch (err) {
    expect(String(err)).toEqual(expect.stringMatching('command failed'));
    return;
  }
  expect(true).toBeFalsy();
});
