// @flow

const path = require('path');
const outdent = require('outdent');
const os = require('os');

const {skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows('#272');

const {packageJson, file, dir, createTestSandbox} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'simple-project',
    version: '1.0.0',
    scripts: {
      cmd1: "bash -c 'echo 'cmd1_result''",
      cmd2: "esy bash -c 'echo 'cmd2_result''",
      cmd3: [['bash', '-c', "echo 'cmd_array_result'"]],
      cmd4: "#{self.target_dir / 'script'}",
      cmd5: "#{$cur__target_dir / 'script'}",
      exec_cmd1: 'esy x script',
      exec_cmd2: 'esy x echo #{self.name}',
      exec_cmd3: [['esy', 'x', 'script']],
      exec_cmd4: [['esy', 'x', 'echo', '#{self.name}']],
      build_cmd: "esy b bash -c 'echo 'build_cmd_result''",
      build_cmd2: 'esy b echo #{self.name}',
      build_cmd3: [['esy', 'b', 'echo', '#{self.name}']],
      build_cmd4: "esy build bash -c 'echo 'build_cmd_result''",
      build_cmd5: 'esy build echo #{self.name}',
      build_cmd6: [['esy', 'build', 'echo', '#{self.name}']],
      printpwd: 'pwd',
    },
    esy: {
      build: [
        ['cp', 'script.sh', "#{self.target_dir / 'script'}"],
        'chmod +x $cur__target_dir/script',
      ],
      install: ['cp $cur__target_dir/script $cur__bin/script'],
    },
    dependencies: {
      dep: '*',
    },
    resolutions: {
      dep: 'link:./dep',
    },
  }),
  file(
    'script.sh',
    outdent`
    #!/bin/bash

    echo 'script_exec_result'
  `,
  ),
  dir(
    'dep',
    packageJson({
      name: 'dep',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
    }),
  ),
  dir('foo'),
];

it('executes scripts', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  await p.esy('build');

  await expect(p.esy('cmd1')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd1_result' + os.EOL}),
  );
  await expect(p.esy('cmd2')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd2_result' + os.EOL}),
  );
  await expect(p.esy('cmd3')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd_array_result' + os.EOL}),
  );
  await expect(p.esy('cmd4')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result' + os.EOL}),
  );
  await expect(p.esy('cmd5')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result' + os.EOL}),
  );

  await expect(p.esy('b cmd1')).rejects.toThrow();
  await expect(p.esy('x cmd1')).rejects.toThrow();

  await expect(p.esy('exec_cmd1')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result\n'}),
  );
  await expect(p.esy('exec_cmd2')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );
  await expect(p.esy('exec_cmd3')).resolves.toEqual(
    expect.objectContaining({stdout: 'script_exec_result' + os.EOL}),
  );
  await expect(p.esy('exec_cmd4')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );

  await expect(p.esy('build_cmd')).resolves.toEqual(
    expect.objectContaining({stdout: 'build_cmd_result' + os.EOL}),
  );
  await expect(p.esy('build_cmd2')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );
  await expect(p.esy('build_cmd3')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );
  await expect(p.esy('build_cmd4')).resolves.toEqual(
    expect.objectContaining({stdout: 'build_cmd_result' + os.EOL}),
  );
  await expect(p.esy('build_cmd5')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );
  await expect(p.esy('build_cmd6')).resolves.toEqual(
    expect.objectContaining({stdout: 'simple-project' + os.EOL}),
  );
});

it('executes scripts even if sandbox is not built', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');

  await expect(p.esy('cmd1')).resolves.toEqual(
    expect.objectContaining({stdout: 'cmd1_result' + os.EOL}),
  );
});

it('does execute scripts in a non-root package scope', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  await p.esy('build');

  await expect(p.esy('-p dep cmd1')).rejects.toMatchObject({
    message: expect.stringMatching('error: unable to resolve command: cmd1'),
  });
});

it("executes script in the package's root", async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  await p.esy('build');
  p.cd('foo');
  const cmd = await p.esy('printpwd');
  const splitPath = cmd.stdout.split('/');
  const folderName = splitPath[splitPath.length - 1];
  expect(folderName).toEqual(expect.not.stringMatching(/foo/));
});

it('run-script executes the specified script', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  const result = await p.esy('run-script printpwd');
  expect(result.stderr).toEqual('');
  expect(result.stdout).toMatch(/^\//); // TODO: handle Windows
});

it('run-script fails when script is not found', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');

  await expect(p.esy('run-script non-existent')).rejects.toMatchObject({
    message: expect.stringMatching("error: Script 'non-existent' not found"),
  });
});
