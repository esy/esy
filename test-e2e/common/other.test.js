// @flow

const path = require('path');

const {promiseExec} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const packageJSON = require('../../package.json');

it('Common - other', async () => {
  expect.assertions(4);
  const esy = args => promiseExec(`${ESYCOMMAND} ${args}`);

  /* 
   * TODO: 
   * Should we use snapshots here?
   * Can we reuse same snapshot for both help commmands?
   */
  const helpExpecting = expect.objectContaining({
    stdout: expect.stringMatching(
      'esy - package.json workflow for native development with Reason/OCaml',
    ),
  });
  await expect(esy('--help')).resolves.toEqual(helpExpecting);
  await expect(esy('help')).resolves.toEqual(helpExpecting);

  const versionExpecting = {
    stdout: packageJSON.version + '\n',
    stderr: '',
  };

  await expect(esy('--version')).resolves.toEqual(versionExpecting);
  await expect(esy('version')).resolves.toEqual(versionExpecting);
});
