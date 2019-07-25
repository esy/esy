var isCi = require('is-ci');

var reporters = ['default'];

// Perhaps a bug in Jest - but resolution fails if
// we give it ["jest-junit"], so we'll resolve
// the complete path directly and pass it in.
let junitPath  = require.resolve("jest-junit");

if (isCi) {
  reporters = reporters.concat([junitPath]);
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
  reporters: reporters,
  collectCoverage: isCi,
};
