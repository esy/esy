// @flow
const path = require('path');

const {genFixture, packageJson, dir} = require('../test/helpers');

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
  const p = await genFixture(...fixture);
  try {
    await p.esy('build');
  } catch (err) {
    expect(String(err)).toEqual(expect.stringMatching('command failed'));
    return;
  }
  expect(true).toBeFalsy();
});
