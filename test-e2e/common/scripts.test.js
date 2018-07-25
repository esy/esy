// @flow

const path = require('path');

const {initFixture} = require('../test/helpers');

it('Common - scripts', async () => {
  expect.assertions(8);
  const p = await initFixture(path.join(__dirname, 'fixtures/scripts-workflow'));
  await p.esy('build');

  await expect(p.esy('cmd1')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd1_result\n'}),
  );
  await expect(p.esy('cmd2')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd2_result\n'}),
  );
  await expect(p.esy('cmd3')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd_array_result\n'}),
  );

  await expect(p.esy('b cmd1')).rejects.toThrow();
  await expect(p.esy('x cmd1')).rejects.toThrow();

  await expect(p.esy('exec_cmd1')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result\n'}),
  );
  await expect(p.esy('exec_cmd2')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result\n'}),
  );

  await expect(p.esy('build_cmd')).resolves.toEqual(
    expect.objectContaining({stdout: 'build_cmd_result\n'}),
  );
});
