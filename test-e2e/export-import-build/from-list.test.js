// @flow

const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const {initFixture} = require('../test/helpers');

it('export import build - from list', async () => {
  const p = await initFixture(path.join(__dirname, './fixtures/symlinks-into-dep'));
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
});
