// @flow

const path = require('path');
const {createTestSandbox, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'sandbox-stress',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      buildsInSource: true,
      build: [
        ['touch', '$cur__root/ok'],
        ['touch', "#{self.root / 'ok'}"],
        ['touch', '$cur__target_dir/ok'],
        ['touch', "#{self.target_dir / 'ok'}"],
        ['touch', '$cur__original_root/.merlin'],
        ['touch', "#{self.original_root / '.merlin'}"],
      ],
      install: [['touch', '$cur__install/ok'], ['touch', "#{self.install / 'ok'}"]],
    },
  }),
];

it('Build - sandbox stress in source', async () => {
  expect.assertions(1);
  const p = await createTestSandbox(...fixture);
  await p.esy('install');
  await p.esy('build');
  const {stdout} = await p.esy('x echo ok');
  expect(stdout).toEqual(expect.stringMatching('ok'));
});
