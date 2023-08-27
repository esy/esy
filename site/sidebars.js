// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // By default, Docusaurus generates a sidebar from the docs folder structure
  docs: {
    workflow: [
      'what-why',
      'getting-started',
      'using-repo-sources-workflow',
      'linking-workflow',
    ],
    reference: [
      'concepts',
      'configuration',
      'environment',
      'commands',
      'low-level-commands',
      'esy-configuration',
      'node-compatibility',
      'faqs',
    ],
    community: ['community'],
    'advanced workflow': [
      'multiple-sandboxes',
      'npm-release',
      'opam-workflow',
      'c-workflow',
      'offline',
    ],
    internals: ['how-it-works', 'development'],
  },
};

module.exports = sidebars;
