/* @flow */

const cp = require('child_process');
const {execSync} = cp;

exports.execFile = function (
  path: string,
  args: Array<string>,
  options: Object,
): Promise<{|stdout: Buffer, stderr: Buffer|}> {
  return new Promise((resolve, reject) => {
    cp.execFile(path, args, options, (error, stdout, stderr) => {
      if (error) {
        reject(`
          ${String(error)}
          STDOUT: ${String(stdout)}
          STDERR: ${String(stderr)}
        `);
      } else {
        resolve({stdout, stderr});
      }
    });
  });
};

exports.exec = function exec(cmd) {
  return execSync(cmd).toString();
};
