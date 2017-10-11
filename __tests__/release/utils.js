/**
 * @flow
 */

import * as path from 'path';
import outdent from 'outdent';
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

export async function readDirectory(...name: string[]) {
  const nodes = await fsRepr.read(path.join(...name));
  return showNode(fsRepr.directory('<root>', nodes));
}

let tempDirectoriesCreatedDuringTestRun = [];

export async function cleanUp() {
  if (tempDirectoriesCreatedDuringTestRun.length > 0) {
    await Promise.all(tempDirectoriesCreatedDuringTestRun.map(p => fs.rmdir(p)));
    tempDirectoriesCreatedDuringTestRun = [];
  }
}

export const esyRoot = path.dirname(path.dirname(path.dirname(__dirname)));
export const esyBin = path.join(esyRoot, 'bin', 'esy');

function spawn(command, args, options) {
  if (process.env.DEBUG != null) {
    console.log('EXECUTE', `${command} ${args.join(' ')}`);
  }
  return child.spawn(command, args, options);
}

export function run(command: string, ...args: string[]) {
  const env = {...process.env, ESY__TEST: 'yes'};
  return spawn(command, args, {env});
}

export function runIn(project: string, command: string, ...args: string[]) {
  const env = {...process.env, ESY__TEST: 'yes'};
  return spawn(command, args, {cwd: project, env});
}

export async function mkdtemp() {
  // We should be using `os.tmpdir()` instead but it's too long so we cannot
  // relocate binaries there.
  const root = '/tmp/';
  const dir = await fs._mkdtemp(root);
  tempDirectoriesCreatedDuringTestRun.push(dir);
  return dir;
}

export function mkdtempSync() {
  // We should be using `os.tmpdir()` instead but it's too long so we cannot
  // relocate binaries there.
  const root = '/tmp/';
  const dir = fs._mkdtempSync(root);
  tempDirectoriesCreatedDuringTestRun.push(dir);
  return dir;
}

export async function packAndNpmInstallGlobal(fixture: Fixture, ...p: string[]) {
  const whatToInstall = path.join(fixture.project, ...p);
  const tarballFilename = await spawn('npm', ['pack'], {
    env: process.env,
    cwd: whatToInstall,
  });
  const stdout = await run(
    'npm',
    'install',
    '--global',
    '--prefix',
    fixture.npmPrefix,
    path.join(whatToInstall, tarballFilename),
  );
  // sanitize stdout so we can match against it
  return sanitizeNpmOutput(stdout);
}

function sanitizeNpmOutput(out) {
  // do random value replacements
  out = out
    .replace(/[\d]+\.[\d]+s/g, 'X.XXXs')
    .replace(/\/tmp\/[A-Za-z0-9]+\//g, '/tmp/TMPDIR/');

  // sort bin links lines at the top, they are in random order in npm
  let lines = out.split('\n');
  const binLinksLines = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === '') {
      binLinksLines.sort();
      lines = binLinksLines.concat(lines.slice(i));
      break;
    }
    binLinksLines.push(lines[i]);
  }
  return lines.join('\n');
}

const DEBUG_TEST_LOC = '/tmp/esydbg';

type Fixture = {
  description: string,
  root: string,
  project: string,
  npmPrefix: string,
};

/**
 * Initialize fixture.
 */
export function initFixtureSync(fixturePath: string) {
  let root;
  if (process.env.DEBUG != null) {
    console.log(outdent`

      Test Debug Notice!
      ------------------

      Test is being executed in DEBUG mode. The location for tests release & installation
      is set to /tmp/esydbg.

      Make sure you run only a single test case at a time with DEBUG as /tmp/esydbg is going
      to be removed before the test run. After test is done with either status, you can go
      into /tmp/esydbg and inspect its contents.

      Note thet if test fails during 'npm install' phase then npm will do a rollback and
      /tmp/esydbg/npm directory will become empty.

    `);
    fs.rmdirSync(DEBUG_TEST_LOC);
    root = DEBUG_TEST_LOC;
  } else {
    root = mkdtempSync();
  }
  const project = path.join(root, 'project');
  const npmPrefix = path.join(root, 'npm');

  fs.copydirSync(fixturePath, project);

  // Patch package.json to include dependency on esy.
  const packageJsonFilename = path.join(project, 'package.json');
  const packageJson = fs.readJsonSync(packageJsonFilename);
  packageJson.devDependencies = packageJson.devDependencies || {};
  packageJson.devDependencies.esy = esyRoot;
  fs.writeFileSync(packageJsonFilename, JSON.stringify(packageJson, null, 2), 'utf8');

  return {
    description: packageJson.description || packageJson.name,
    root,
    project,
    npmPrefix,
  };
}
