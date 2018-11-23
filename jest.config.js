var isCi = require('is-ci');

var reporters = ['default'];

if (isCi) {
  reporters = reporters.concat(['jest-junit']);
}

module.exports = {
  resolver: require.resolve('jest-pnp-resolver'),
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
