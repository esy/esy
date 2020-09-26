var isCi = require('is-ci');
var path = require('path');

var reporters = ['default'];

// Perhaps a bug in Jest - but resolution fails if
// we give it ["jest-junit"], so we'll resolve
// the complete path directly and pass it in.
let junitPath  = require.resolve("jest-junit");
const isWindows = process.platform === 'win32';

if (isCi) {
  reporters = reporters.concat([junitPath]);
}

var __ESY__base = path.join(__dirname, '_build', 'install', 'default', 'bin');
var __ESY__ = path.join(__ESY__base, 'esy');

if (isWindows) {
  __ESY__ = __ESY__ + '.exe';
}

process.env.PATH = __ESY__base + (isWindows ? ';': ':') + process.env.PATH;

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
  globals: {__ESY__: __ESY__}
};
