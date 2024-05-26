// @ts-check
// Note: type annotations allow type checking and IDEs autocompletion

const {themes} = require('prism-react-renderer');
const lightTheme = themes.github;
const darkTheme = themes.dracula;

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'esy',
  tagline: 'Easy package management for native Reason, OCaml and more',
  url: 'https://esy.sh',
  baseUrl: '/',
  organizationName: 'esy',
  projectName: 'esy-website',
  favicon: '/img/block-red.svg',
  baseUrl: '/',
  // GitHub pages deployment config.
  organizationName: 'esy',
  projectName: 'esy',

  onBrokenLinks: 'log',
  onBrokenMarkdownLinks: 'log',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          showLastUpdateAuthor: true,
          showLastUpdateTime: true,
          editUrl: 'https://github.com/esy/esy/tree/master/docs/',
          path: '../docs',
          sidebarPath: require.resolve('./sidebars.js'),
        },
        blog: {
          showReadingTime: true,
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/docusaurus-social-card.jpg',
      navbar: {
        title: 'esy',
        logo: {
          src: '/img/block-red.svg',
        },
        items: [
          {
            to: 'docs/getting-started',
            label: 'Getting started',
            position: 'left',
          },
          {
            to: 'docs/community',
            label: 'Community',
            position: 'left',
          },
          {
            href: 'https://github.com/esy/esy',
            label: 'GitHub',
            position: 'left',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              {
                label: 'Tutorial',
                to: '/docs/getting-started',
              },
            ],
          },
          {
            title: 'Community',
            items: [
              {
                label: 'Discord',
                href: 'https://discord.gg/reasonml',
              },
              {
                label: 'Twitter',
                href: 'https://twitter.com/reasonml',
              },
            ],
          },
          {
            title: 'More',
            items: [
              {
                label: 'Blog',
                to: '/blog',
              },
              {
                label: 'GitHub',
                href: 'https://github.com/esy/esy',
              },
            ],
          },
        ],
      },
      algolia: {
        appId: 'NVSKCZKSMV',
        apiKey: '55792f72558bc8f2ad2ca591de82f945',
        indexName: 'esysh',
        // TODO figure out how to set insights: true, // Optional, automatically send insights when user interacts with search results
      },
      prism: {
        additionalLanguages: ['diff'],
        theme: lightTheme,
        darkTheme: darkTheme,
      },
    }),
};

module.exports = config;
