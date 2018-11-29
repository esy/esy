// @flow
const path = require('path');

const helpers = require('../test/helpers');

const fixture = [
  helpers.packageJson({
    name: 'errorneous-build',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      build: ['false'],
    },
  }),
];

it('Exists with a non-zero exit code if build fails', async () => {
  const p = await helpers.createTestSandbox(...fixture);
  await p.esy('install');
  try {
    await p.esy('build');
  } catch (err) {
    expect(String(err)).toEqual(expect.stringMatching('command failed'));
    return;
  }
  expect(true).toBeFalsy();
});
