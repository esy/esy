// @flow

const fs = require('fs');
const path = require('path');
const outdent = require('outdent');

const isWindows = process.platform === 'win32';

let input = process.argv[2];

if (input == null) {
  console.warn('error: provide input as argument');
  process.exit(1);
}

const output = input.replace(/\.[^\.]+$/, '.cmd');
const script = './' + path.basename(input);

if (isWindows) {
  fs.writeFileSync(
    output,
    outdent`
      @${JSON.stringify(process.execPath)} ${JSON.stringify(script)} %*
    `,
  );
} else {
  fs.writeFileSync(
    output,
    outdent`
      #!${process.execPath}
      require(${JSON.stringify(script)});
    `,
  );
  fs.chmodSync(output, 0755);
}
