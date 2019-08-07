var isCi = require('is-ci');
var cp = require('child_process');
var path = require('path');
var isWindows = process.platform === 'win32';

var __ESY__ = path.join(__dirname, '_build', 'install', 'default', 'bin', 'esy');

if (isWindows) {
  __ESY__ = __ESY__ + '.exe';
}

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
  reporters: ['default'],
  collectCoverage: isCi,
  globals: {__ESY__: __ESY__},
};
