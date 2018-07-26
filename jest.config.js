const runSlowTests = Boolean(process.env.SLOWTEST);

const projects = [
  {
    displayName: 'e2e:fast',
    moduleFileExtensions: ['js'],
    testMatch: ['<rootDir>/test-e2e/**/*.test.js'],
  }
];

if (runSlowTests) {
  projects.push({
    displayName: 'e2e:slow',
    moduleFileExtensions: ['js'],
    testMatch: ['<rootDir>/test-e2e/**/*.slow-test.js'],
  });
}

module.exports = {
  projects: projects,
};
