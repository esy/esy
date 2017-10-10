/**
 * @flow
 */

import * as path from 'path';
import * as fs from '../../src/lib/fs';
import * as child from '../../src/lib/child_process';
import * as fsRepr from '../../src/lib/fs-repr';

function showNode(node: fsRepr.Node, indent = 0): string {
  const indentStr = indent > 0 ? '| '.repeat(indent) : '';
  if (node.type === 'directory') {
    return [indentStr + node.name, ...node.nodes.map(n => showNode(n, indent + 1))].join(
      '\n',
    );
  } else if (node.type === 'file') {
    return indentStr + node.name;
  } else if (node.type === 'link') {
    return indentStr + node.name;
  }
  throw new Error(`unknown node: ${JSON.stringify(node)}`);
}

let tempDirectoriesCreatedDuringTestRun = [];

export async function createProject(packageJson: any, ...extra: fsRepr.Node[]) {
  const nodes = [
    fsRepr.file('package.json', JSON.stringify(packageJson, null, 2)),
    ...extra,
  ];
  const root = await mkdtemp();
  await fsRepr.write(root, nodes);
  return root;
}

export async function readDirectory(...name: string[]) {
  const nodes = await fsRepr.read(path.join(...name));
  return showNode(fsRepr.directory('<root>', nodes));
}

export async function cleanUp() {
  if (tempDirectoriesCreatedDuringTestRun.length > 0) {
    await Promise.all(tempDirectoriesCreatedDuringTestRun.map(p => fs.rmdir(p)));
    tempDirectoriesCreatedDuringTestRun = [];
  }
}

export const esyRoot = path.dirname(path.dirname(path.dirname(__dirname)));
export const esyBin = path.join(esyRoot, 'bin', 'esy');

export function run(command: string, ...args: string[]) {
  if (process.env.DEBUG != null) {
    console.log('EXECUTE', command, args);
  }
  const env = {...process.env, ESY__TEST: 'yes'};
  return child.spawn(command, args, {env});
}

export function runIn(project: string, command: string, ...args: string[]) {
  if (process.env.DEBUG != null) {
    console.log('EXECUTE', command, args, 'CWD:', project);
  }
  const env = {...process.env, ESY__TEST: 'yes'};
  return child.spawn(command, args, {cwd: project, env});
}

export const file = fsRepr.file;
export const directory = fsRepr.directory;

export async function mkdtemp() {
  // We should be using `os.tmpdir()` instead but it's too long so we cannot
  // relocate binaries there.
  const root = '/tmp/';
  const dir = await fs._mkdtemp(root);
  tempDirectoriesCreatedDuringTestRun.push(dir);
  return dir;
}

export async function packAndNpmInstallGlobal(fixture: Fixture, ...p: string[]) {
  const whatToInstall = path.join(fixture.project, ...p);
  const tarballFilename = await child.spawn('npm', ['pack'], {cwd: whatToInstall});
  await run(
    'npm',
    'install',
    '--global',
    '--prefix',
    fixture.npmPrefix,
    path.join(whatToInstall, tarballFilename),
  );
}

type Fixture = {
  root: string,
  project: string,
  npmPrefix: string,
};

export async function initFixture(fixturePath: string) {
  const root = await (process.env.DEBUG != null ? '/tmp/esytest' : mkdtemp());
  const project = path.join(root, 'project');
  const npmPrefix = path.join(root, 'npm');

  await fs.copydir(fixturePath, project);

  // patch package.json to include dependency on esy
  const packageJsonFilename = path.join(project, 'package.json');
  const packageJson = await fs.readJson(packageJsonFilename);
  packageJson.devDependencies = packageJson.devDependencies || {};
  packageJson.devDependencies.esy = esyRoot;
  await fs.writeFile(packageJsonFilename, JSON.stringify(packageJson, null, 2), 'utf8');

  return {
    root,
    project,
    npmPrefix,
  };
}
