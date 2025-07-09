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
      'ocaml-compiler'
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
      'portable-reason-ocaml',
      'multiple-sandboxes',
      'npm-release',
      'opam-workflow',
      'c-workflow',
      'offline',
      'esy-installer'
    ],
    contributing: [
      'contributing/how-it-works',
      'contributing/building-from-source',
      'contributing/repository-structure',
      'contributing/running-tests',
      'contributing/website-and-docs',
      'contributing/ci',
      'contributing/release-process',
    ],
  },
};

module.exports = sidebars;
