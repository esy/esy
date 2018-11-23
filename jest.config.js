var isCi = require('is-ci');

var reporters = ['default'];

if (isCi) {
  reporters = reporters.concat(['jest-junit']);
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
