/**
 * @no-flow-yet
 */

const child_process = require('child_process');
const path = require('path');
const chalk = require('chalk');

const RUNTIME = require.resolve('./runtime.sh');
const ESYCOMMAND = require.resolve('../bin/esy');

module.exports = testRunner;

function testRunner(globalConfig, config, environment, runtime, testPath) {
  const start = +new Date();
  const source = `
    export ESYCOMMAND="${ESYCOMMAND}"
    source "${RUNTIME}"
    source "${testPath}"
    doTest
  `;
  return spawn('/bin/bash', ['-c', source], {cwd: path.dirname(testPath)}).then(
    () => {
      const end = +new Date();
      return success({testPath, start, end});
    },
    err => {
      const end = +new Date();
      if (err.EXIT_CODE === 66) {
        return skipped({testPath, start, end, message: chalk.yellow(err.stdout)});
      } else {
        return failure({testPath, start, end, failureMessage: err.stdout});
      }
    }
  );
}

function success({testPath, start, end}) {
  return {
    console: null,
    failureMessage: null,
    numFailingTests: 0,
    numPassingTests: 1,
    numPendingTests: 0,
    perfStats: {
      end,
      start,
    },
    skipped: false,
    snapshot: {
      added: 0,
      fileDeleted: false,
      matched: 0,
      unchecked: 0,
      unmatched: 0,
      updated: 0,
    },
    sourceMaps: {},
    testExecError: null,
    testFilePath: testPath,
    testResults: [
      {
        ancestorTitles: [],
        duration: end - start,
        failureMessages: [],
        fullName: 'Assertion',
        numPassingAsserts: 1,
        status: 'passed',
        title: 'passed',
      },
    ],
  };
}

function skipped({testPath, start, end, message}) {
  return {
    console: null,
    failureMessage: message,
    numFailingTests: 0,
    numPassingTests: 0,
    numPendingTests: 1,
    perfStats: {
      end,
      start,
    },
    skipped: true,
    snapshot: {
      added: 0,
      fileDeleted: false,
      matched: 0,
      unchecked: 0,
      unmatched: 0,
      updated: 0,
    },
    sourceMaps: {},
    testExecError: null,
    testFilePath: testPath,
    testResults: [
      {
        ancestorTitles: [],
        duration: end - start,
        failureMessages: [],
        fullName: 'Assertion',
        numPassingAsserts: 1,
        status: 'skipped',
        title: 'skipped',
      },
    ],
  };
}

function failure({testPath, start, end, failureMessage}) {
  return {
    console: null,
    failureMessage: chalk.red(failureMessage),
    numFailingTests: 1,
    numPassingTests: 0,
    numPendingTests: 0,
    perfStats: {
      end,
      start,
    },
    skipped: false,
    snapshot: {
      added: 0,
      fileDeleted: false,
      matched: 0,
      unchecked: 0,
      unmatched: 0,
      updated: 0,
    },
    sourceMaps: {},
    testExecError: null,
    testFilePath: testPath,
    testResults: [
      {
        ancestorTitles: [],
        duration: end - start,
        failureMessages: [],
        fullName: 'Assertion',
        numPassingAsserts: 0,
        status: 'failed',
        title: 'failed',
      },
    ],
  };
}

function spawn(program, args, opts = {}, onData) {
  return new Promise((resolve, reject) => {
    const proc = child_process.spawn(program, args, opts);

    let processingDone = false;
    let processClosed = false;
    let err = null;

    let stdout = '';

    proc.on('error', err => {
      if (err.code === 'ENOENT') {
        reject(new Error(`Couldn't find the binary ${program}`));
      } else {
        reject(err);
      }
    });

    function updateStdout(chunk) {
      stdout += chunk;
      if (onData) {
        onData(chunk);
      }
    }

    function finish() {
      if (err) {
        reject(err);
      } else {
        resolve(stdout.trim());
      }
    }

    if (typeof opts.process === 'function') {
      opts.process(proc, updateStdout, reject, function() {
        if (processClosed) {
          finish();
        } else {
          processingDone = true;
        }
      });
    } else {
      if (proc.stderr) {
        proc.stderr.on('data', updateStdout);
      }

      if (proc.stdout) {
        proc.stdout.on('data', updateStdout);
      }

      processingDone = true;
    }

    proc.on('close', code => {
      if (code >= 1) {
        stdout = stdout.trim();
        // TODO make this output nicer
        err = new Error(
          [
            'Command failed.',
            `Exit code: ${code}`,
            `Command: ${program}`,
            `Arguments: ${args.join(' ')}`,
            `Directory: ${opts.cwd || process.cwd()}`,
            `Output:\n${stdout}`,
          ].join('\n')
        );
        // $FlowFixMe: ...
        err.EXIT_CODE = code;
        // $FlowFixMe: ...
        err.stdout = stdout;
      }

      if (processingDone || err) {
        finish();
      } else {
        processClosed = true;
      }
    });
  });
}
