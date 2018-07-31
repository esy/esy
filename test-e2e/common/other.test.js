// @flow

const {promiseExec, ESYCOMMAND} = require('../test/helpers');

it('Common - other', async () => {
  expect.assertions(4);
  const esy = args => promiseExec(`${ESYCOMMAND} ${args}`);

  await expect(esy('--help')).resolves.not.toThrow();
  await expect(esy('help')).resolves.not.toThrow();

  await expect(esy('--version')).resolves.not.toThrow();
  await expect(esy('version')).resolves.not.toThrow();
});
