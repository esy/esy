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
};
