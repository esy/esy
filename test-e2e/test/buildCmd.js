// @flow

const fs = require('fs');
const path = require('path');

const isWindows = process.platform === 'win32';

let input = process.argv[2];

if (input == null) {
  console.warn('error: provide input as argument');
  process.exit(1);
}

const output = input.replace(/\.[^\.]+$/, '.cmd');
const script = './' + path.basename(input);

if (isWindows) {
  let args = JSON.stringify('%~dp0\\' + script);
  let program = `@${JSON.stringify(process.execPath)} ${args} %*`;
  fs.writeFileSync(output, program);
} else {
  let program = `#!${process.execPath}\nrequire(${JSON.stringify(script)});`;
  fs.writeFileSync(output, program);
  fs.chmodSync(output, 0755);
}
