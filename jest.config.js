module.exports = {
  displayName: 'e2e:fast',
  moduleFileExtensions: ['js'],
  testMatch: ['<rootDir>/test-e2e/**/*.test.js'],
  modulePathIgnorePatterns: [
    '<rootDir>/esy-install/',
    '<rootDir>/node_modules/',
    '<rootDir>/test-e2e/build/fixtures/'
  ]
};
