module.exports = {
  projects: [
    {
      displayName: 'e2e - JavaScript',
      moduleFileExtensions: ['js'],
      testMatch: ['<rootDir>/**/*.test.js'],
    },
    {
      moduleFileExtensions: ['sh'],
      displayName: 'e2e - sh',
      testRunner: './jest-bash-runner/index.js',
      testMatch: ['<rootDir>/**/*-test.sh'],
    },
  ],
};
