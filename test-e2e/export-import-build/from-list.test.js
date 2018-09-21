// @flow

const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

function makeFixture(p) {
  return [
    packageJson({
      name: 'app',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: ['ln -s #{dep.bin / dep.name}.exe #{self.bin / self.name}.exe'],
      },
      dependencies: {
        dep: '*',
      },
    }),
    dir(
      'node_modules',
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          license: 'MIT',
          esy: {
            build: ['ln -s #{subdep.bin / subdep.name}.exe #{self.bin / self.name}.exe'],
          },
          dependencies: {
            subdep: '*',
          },
        }),
        file(
          '_esylink',
          JSON.stringify({
            source: `path:.`,
          }),
        ),
        dir(
          'node_modules',
          dir(
            'subdep',
            packageJson({
              name: 'subdep',
              version: '1.0.0',
              license: 'MIT',
              esy: {
                buildsInSource: true,
                build: 'chmod +x #{self.name}.exe',
                install: 'cp #{self.name}.exe #{self.bin / self.name}.exe',
              },
            }),
            file('_esylink', JSON.stringify({source: `path:.`})),
            dummyExecutable('subdep'),
          ),
        ),
      ),
    ),
  ];
}

it('export import build - from list', async () => {
  const p = await helpers.createTestSandbox();
  await p.fixture(...makeFixture(p));
  await p.esy('build');

  await p.esy('export-dependencies');

  const list = await fs.readdir(path.join(p.projectPath, '_export'));
  await fs.writeFile(
    path.join(p.projectPath, 'list.txt'),
    list.map(x => path.join('_export', x)).join('\n') + '\n',
  );

  const expected = [
    expect.stringMatching('dep-1.0.0'),
    expect.stringMatching('subdep-1.0.0'),
  ];

  const delResult = await del(path.join(p.esyPrefixPath, '3_*', 'i', '*'), {force: true});
  expect(delResult).toEqual(expect.arrayContaining(expected));

  await p.esy('import-build --from ./list.txt');

  const ls = await fs.readdir(path.join(p.esyPrefixPath, '/3/i'));
  expect(ls).toEqual(expect.arrayContaining(expected));

  {
    const {stdout} = await p.esy('subdep.exe');
    expect(stdout.trim()).toBe('__subdep__');
  }
  {
    const {stdout} = await p.esy('dep.exe');
    expect(stdout.trim()).toBe('__subdep__');
  }
  {
    const {stdout} = await p.esy('x app.exe');
    expect(stdout.trim()).toBe('__subdep__');
  }
});
