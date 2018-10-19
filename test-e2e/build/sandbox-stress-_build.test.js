// @flow

const path = require('path');
const {createTestSandbox, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'sandbox-stress',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      buildsInSource: '_build',
      build: [
        ['mkdir', '-p', '$cur__root/_build'],
        ['touch', '$cur__root/_build/ok'],
        ['touch', "#{self.root / '_build' / 'ok'}"],
        ['touch', '$cur__root/pkg.install'],
        ['touch', "#{self.root / 'pkg.install'}"],
        ['touch', '$cur__root/pkg.opam'],
        ['touch', "#{self.root / 'pkg.opam'}"],
        ['touch', '$cur__root/jbuild-ignore'],
        ['touch', "#{self.root / 'jbuild-ignore'}"],
        ['touch', '$cur__target_dir/ok'],
        ['touch', "#{self.target_dir / 'ok'}"],
        ['touch', '$cur__original_root/.merlin'],
        ['touch', "#{self.original_root / '.merlin'}"],
      ],
      install: [['touch', '$cur__install/ok'], ['touch', "#{self.install / 'ok'}"]],
    },
  }),
];

it('Build - sandbox stress _build', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  await p.esy('build');

  const {stdout} = await p.esy('x echo ok');
  expect(stdout).toEqual(expect.stringMatching('ok'));
});
