module.exports = {
  projects: [
    {
      displayName: 'e2e - JavaScript',
      moduleFileExtensions: ['js'],
      runner: 'jest-runner',
      testMatch: ['<rootDir>/**/*.test.js'],
    },
    {
      moduleFileExtensions: ['sh'],
      displayName: 'e2e - sh',
      runner: './jest-bash-runner/index.js',
      testMatch: ['<rootDir>/**/*-test.sh'],
    },
  ],
};
