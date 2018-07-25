// @flow

const {promiseExec} = require('../test/helpers');
const ESYCOMMAND = require.resolve('../../bin/esy');

it('Common - other', async () => {
  expect.assertions(4);
  const esy = args => promiseExec(`${ESYCOMMAND} ${args}`);

  await expect(esy('--help')).resolves.not.toThrow();
  await expect(esy('help')).resolves.not.toThrow();

  await expect(esy('--version')).resolves.not.toThrow();
  await expect(esy('version')).resolves.not.toThrow();
});
