var isCi = require('is-ci');
var path = require('path');
var fs = require('fs');
var reporters = ['default'];

// Perhaps a bug in Jest - but resolution fails if
// we give it ["jest-junit"], so we'll resolve
// the complete path directly and pass it in.
let junitPath = require.resolve('jest-junit');
const isWindows = process.platform === 'win32';

if (isCi) {
  reporters = reporters.concat([junitPath]);
}

var __ESY__;
if (process.platform !== 'linux') {
  var __ESY__base = path.join(__dirname, '_build', 'install', 'default', 'bin');
  __ESY__ = path.join(__ESY__base, 'esy');
} else {
  const testEsyPrefix = path.join(__dirname, '.test-esy');
  if (process.platform === 'linux') {
    fs.rmSync(testEsyPrefix, {force: true, recursive: true});
    fs.mkdirSync(testEsyPrefix, {recursive: true});
    fs.cpSync(path.join(__dirname, '_build', 'install', 'default'), testEsyPrefix, {
      recursive: true,
      dereference: true,
    });
  }
  __ESY__ = path.join(testEsyPrefix, 'bin', 'esy');
}

if (isWindows) {
  __ESY__ += '.exe';
}

process.env.PATH = __ESY__base + (isWindows ? ';' : ':') + process.env.PATH;

module.exports = {
  displayName: 'e2e:fast',
  moduleFileExtensions: ['js'],
  testMatch: ['<rootDir>/test-e2e/**/*.test.js'],
  testEnvironment: 'node',
  modulePathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/test-e2e/build/fixtures/',
  ],
  coverageReporters: ['text-summary', 'json', 'html', 'cobertura'],
  reporters: reporters,
  collectCoverage: isCi,
  globals: {__ESY__: __ESY__},
};
