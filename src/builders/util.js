/**
 * @flow
 */

import type {BuildSpec, Config} from '../types';

import * as child from 'child_process';
import * as fs from '../lib/fs';
import * as path from '../lib/path';
import outdent from 'outdent';

type ConfigSpec = {
  allowFileWrite?: Array<?string>,
  denyFileWrite?: Array<?string>,
};

export function renderSandboxSbConfig(
  spec: BuildSpec,
  config: Config<path.Path>,
  sandboxSpec?: ConfigSpec = {},
): string {
  const isRoot = spec.packagePath === '';
  const subpathList = pathList =>
    pathList
      ? pathList
          .filter(Boolean)
          .map(path => `(subpath "${path}")`)
          .join(' ')
      : '';

  // TODO: Right now the only thing this sandbox configuration does is it
  // disallows writing into locations other than $cur__root,
  // $cur__target_dir and $cur__install. We should implement proper out of
  // source builds and also disallow $cur__root.
  // TODO: Try to use (deny default) and pick a set of rules for builds to
  // proceed (it chokes on xcodebuild for now if we disable reading "/" and
  // networking).
  return outdent`
    (version 1.0)
    (allow default)

    (deny file-write*
      (subpath "/"))

    (allow file-write*
      (literal "/dev/null")

      ${spec.buildType === '_build'
        ? `
        ; $cur__root/_build
         (subpath "${config.getRootPath(spec, '_build')}")


        ; $cur__root/*/NAME.install
         (regex "^${config.getRootPath(spec, '.*', '[^/]*\\.install')}$")
        ; $cur__root/NAME.install
         (regex "^${config.getRootPath(spec, '[^/]*\\.install')}$")

        ; $cur__root/NAME.opam
         (regex "^${config.getRootPath(spec, '[^/]*\\.opam')}$")

        ; $cur__root/jbuild-ignore
         (regex "^${config.getRootPath(spec, 'jbuild-ignore')}$")
        `
        : ``};

      ; $cur__original_root/*/.merlin
      (regex "^${config.getSourcePath(spec, '.*', '\\.merlin')}$")
      ; $cur__original_root/.merlin
      (regex "^${config.getSourcePath(spec, '\\.merlin')}$")

      ; $cur__target_dir
      (subpath "${config.getBuildPath(spec)}")

      ; $cur__install
      (subpath "${config.getInstallPath(spec)}")

      ; config.allowFileWrite
      ${subpathList(sandboxSpec.allowFileWrite)}
    )

  `;
}

export async function rewritePathInFile(
  filename: string,
  origPath: string,
  destPath: string,
) {
  const stat = await fs.stat(filename);
  if (!stat.isFile()) {
    return;
  }
  const content = await fs.readFileBuffer(filename);
  let offset = content.indexOf(origPath);
  const needRewrite = offset > -1;
  while (offset > -1) {
    content.write(destPath, offset);
    offset = content.indexOf(origPath);
  }
  if (needRewrite) {
    await fs.writeFile(filename, content);
  }
}

export async function rewritePathInSymlink(
  filename: string,
  origPath: string,
  destPath: string,
) {
  const stat = await fs.lstat(filename);
  if (!stat.isSymbolicLink()) {
    return;
  }
  const linkPath = path.resolve(path.dirname(filename), await fs.readlink(filename));
  if (linkPath.indexOf(origPath) !== 0) {
    return;
  }
  const nextTargetPath = path.join(destPath, path.relative(origPath, linkPath));
  await fs.unlink(filename);
  await fs.fsSymlink(nextTargetPath, filename);
}

export function exec(
  ...args: *
): {process: child.ChildProcess, exit: Promise<{code: number, signal: string}>} {
  const process = child.exec(...args);
  const exit = new Promise(resolve => {
    process.on('exit', (code, signal) => resolve({code, signal}));
  });
  return {process, exit};
}
