import React, {useState} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import {useColorMode} from '@docusaurus/theme-common';
import Layout from '@theme/Layout';
import CodeBlock from '@theme/CodeBlock';
import Terminal, {ColorMode, TerminalOutput} from 'react-terminal-ui';

import styles from './index.module.css';

const TerminalController = (props = {}) => {
  // Terminal has 100% width by default so it should usually be wrapped in a container div
  const {colorMode} = useColorMode();
  return (
    <Terminal
      name="Getting started with esy"
      colorMode={colorMode === 'light' ? ColorMode.Light : ColorMode.Dark}
      height="180px"
    >
      {props.lines.map((line, i) => (
        <TerminalOutput key={i}>{line}</TerminalOutput>
      ))}
    </Terminal>
  );
};

const quickStart = `npm install -g esy

# Clone example, install dependencies, then build
git clone https://github.com/esy-ocaml/hello-reason.git
cd hello-reason
esy`;
function Homepage() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <main className={clsx('container', styles.heroBanner)}>
      <section className="row">
        <section className={clsx('col', styles.title)}>
          <h1 className="hero__title">{siteConfig.title}</h1>
          <p className="hero__subtitle">{siteConfig.tagline}</p>
          <Link
            className={clsx(styles.buttons, 'button button--secondary button--lg')}
            to="/docs/getting-started"
          >
            Get Started
          </Link>
        </section>
      </section>
    </main>
  );
}
// <CodeBlock language="bash">{quickStart}</CodeBlock>

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={`Documentation | ${siteConfig.title}`}
      description="Package manager for Reason, OCaml and more"
      wrapperClassName={styles.minHeight}
    >
      <Homepage />
    </Layout>
  );
}
