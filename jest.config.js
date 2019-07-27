var isCi = require('is-ci');
var cp = require('child_process');

var __ESY__ = cp
  .execSync('esy dune exec which esy')
  .toString()
  .trim();

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
