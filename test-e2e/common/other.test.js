// @flow

const {createTestSandbox} = require('../test/helpers');

it('Common - other', async () => {
  expect.assertions(4);

  const p = await createTestSandbox();

  await expect(p.esy('--help')).resolves.not.toThrow();
  await expect(p.esy('help')).resolves.not.toThrow();

  await expect(p.esy('--version')).resolves.not.toThrow();
  await expect(p.esy('version')).resolves.not.toThrow();
});
