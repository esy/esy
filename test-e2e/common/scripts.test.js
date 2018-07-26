// @flow

const path = require('path');
const outdent = require('outdent');

const {packageJson, file, genFixture} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "simple-project",
    "version": "1.0.0",
    "scripts": {
      "cmd1": "bash -c 'echo 'cmd1_result''",
      "cmd2": "esy bash -c 'echo 'cmd2_result''",
      "cmd3": [["bash", "-c", "echo 'cmd_array_result'"]],
      "cmd4": "#{self.target_dir / 'script'}",
      "exec_cmd1": "esy x script",
      "exec_cmd2": [["esy", "x", "script"]],
      "build_cmd": "esy b bash -c 'echo 'build_cmd_result''"
    },
    "esy": {
      "build": [
        ["cp", "script.sh", "#{self.target_dir / 'script'}"],
        "chmod +x $cur__target_dir/script"
      ],
      "install": ["cp $cur__target_dir/script $cur__bin/script"]
    },
  }),
  file('script.sh', outdent`
    #!/bin/bash

    echo 'script_exec_result'
  `)
];

it('Common - scripts', async () => {
  const p = await genFixture(...fixture);
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
  await expect(p.esy('cmd4')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result\n'}),
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
