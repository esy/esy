module.exports = {
  moduleFileExtensions: ['sh'],
  testRunner: './jest-bash-runner/index.js',
  testMatch: ['**/__tests__/**/*-test.sh'],
  modulePathIgnorePatterns: [
    '<rootDir>/__tests__/fixtures/',
    '<rootDir>/__tests__/build/fixtures',
    '<rootDir>/esy-install',
    '<rootDir>/dist',
    '<rootDir>/esyInstallCache-3.x.x',
  ],
  transformIgnorePatterns: ['<rootDir>/node_modules/(?!@esy-ocaml/esy-install)'],
};
