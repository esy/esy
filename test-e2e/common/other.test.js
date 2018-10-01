// @flow

const helpers = require('../test/helpers');

it('Common - other', async () => {
  const p = await helpers.createTestSandbox();

  await expect(p.esy('--help')).resolves.not.toThrow();
  await expect(p.esy('help')).resolves.not.toThrow();

  await expect(p.esy('--version')).resolves.not.toThrow();
  await expect(p.esy('version')).resolves.not.toThrow();
});
