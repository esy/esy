/**
 * @flow
 */

import * as fs from '../../lib/fs';
import * as FSRepr from '../../lib/fs-repr';
import {create} from '../project-sandbox';

function pkg(packageJson, ...dependencies) {
  const nodes = [FSRepr.file('package.json', packageJson)];
  if (dependencies.length > 0) {
    nodes.push(FSRepr.directory('node_modules', dependencies));
  }
  return FSRepr.directory(packageJson.name, nodes);
}

describe('build-sandbox', function() {
  let directoriesToCleanup = [];

  async function prepareSandbox(nodes: FSRepr.Node[]): Promise<string> {
    const tempdir = await fs.mkdtemp('esy-test-sandbox');
    directoriesToCleanup.push(tempdir);
    await FSRepr.write(tempdir, nodes);
    return tempdir;
  }

  beforeEach(function() {
    directoriesToCleanup = [];
  });

  afterEach(async function() {
    for (const dirname of directoriesToCleanup) {
      try {
        await fs.unlink(dirname);
      } catch (_err) {}
    }
  });

  test('builds a sandbox from a single package', async function() {
    const sandboxDir = await prepareSandbox(
      pkg({
        name: 'app',
        version: '0.1.0',
        _resolved: 'app',
      }).nodes,
    );
    const sandbox = await create(sandboxDir);
    expect(sandbox.root).toMatchSnapshot();
  });

  test('builds a sandbox from a package with deps', async function() {
    const sandboxDir = await prepareSandbox(
      pkg(
        {
          name: 'app',
          version: '0.1.0',
          dependencies: {
            dep: '*',
          },
          _resolved: 'app',
        },
        pkg({
          name: 'dep',
          version: '0.1.0',
          _resolved: 'dep',
        }),
      ).nodes,
    );
    const sandbox = await create(sandboxDir);
    expect(sandbox.root).toMatchSnapshot();
  });

  test('error: missing a dep', async function() {
    const sandboxDir = await prepareSandbox(
      pkg({
        name: 'app',
        version: '0.1.0',
        dependencies: {
          dep: '*',
        },
        _resolved: 'app',
      }).nodes,
    );
    const sandbox = await create(sandboxDir);
    expect(sandbox.root).toMatchSnapshot();
  });

  test('error: circular deps', async function() {
    const sandboxDir = await prepareSandbox(
      pkg(
        {
          name: 'app',
          version: '0.1.0',
          dependencies: {
            dep: '*',
          },
          _resolved: 'app',
        },
        pkg({
          name: 'dep',
          version: '0.1.0',
          dependencies: {
            app: '*',
          },
          _resolved: 'dep',
        }),
      ).nodes,
    );
    const sandbox = await create(sandboxDir);
    expect(sandbox.root).toMatchSnapshot();
  });
});
