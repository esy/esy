module.exports = {
  projects: [
    {
      displayName: 'e2e:js',
      moduleFileExtensions: ['js'],
      testMatch: ['<rootDir>/test-e2e/**/*.test.js'],
    },
    {
      moduleFileExtensions: ['sh', 'js'],
      displayName: 'e2e:sh',
      testRunner: '<rootDir>/jest-bash-runner/index.js',
      testMatch: ['<rootDir>/test-e2e/**/*-test.sh'],
    },
  ],
};
