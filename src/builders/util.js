/**
 * @flow
 */

import type {BuildSpec, BuildConfig, BuildEnvironment} from '../types';

import * as child from 'child_process';
import * as fs from '../lib/fs';
import outdent from 'outdent';

type ConfigSpec = {
  allowFileWrite?: Array<?string>,
  denyFileWrite?: Array<?string>,
};

export function renderSandboxSbConfig(
  spec: BuildSpec,
  config: BuildConfig,
  sandboxSpec?: ConfigSpec = {},
): string {
  const subpathList = pathList =>
    pathList ? pathList.filter(Boolean).map(path => `(subpath "${path}")`).join(' ') : '';

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

      ; $cur__target_dir
      (subpath "${config.getBuildPath(spec)}")

      ; $cur__install
      (subpath "${config.getInstallPath(spec)}")

      ; config.allowFileWrite
      ${subpathList(sandboxSpec.allowFileWrite)}
    )

  `;
}

export function renderEnv(env: BuildEnvironment): string {
  return Array.from(env.values())
    .map(env => `export ${env.name}="${env.value}";`)
    .join('\n');
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

export function exec(
  ...args: *
): {process: child.ChildProcess, exit: Promise<{code: number, signal: string}>} {
  const process = child.exec(...args);
  const exit = new Promise(resolve => {
    process.on('exit', (code, signal) => resolve({code, signal}));
  });
  return {process, exit};
}
