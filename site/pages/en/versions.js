/**
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

const React = require('react');

const CompLibrary = require('../../core/CompLibrary');

const Container = CompLibrary.Container;

const CWD = process.cwd();

const versions = require(`${CWD}/versions.json`);

function Versions(props) {
  const {config: siteConfig} = props;
  const latestVersion = versions[0];
  const repoUrl = `https://github.com/${siteConfig.organizationName}/${
    siteConfig.projectName
  }`;
  return (
    <div className="docMainWrapper wrapper">
      <Container className="mainContainer versionsContainer">
        <div className="post">
          <header className="postHeader">
            <h1>{siteConfig.title} versions</h1>
          </header>
          <h3 id="latest">{latestVersion} (latest)</h3>
          <p>
            See <a href={`${siteConfig.baseUrl}${siteConfig.docsUrl}/${props.language}/getting-started.html`}>documentation</a> or go directly to{' '}
            <a href={`${siteConfig.baseUrl}${siteConfig.docsUrl}/${props.language}/commands.html`}>commands</a> reference.
          </p>
          <p>
            Install with:
          </p>
          <pre>
            <code className="hljs langiage-shell">npm install -g esy</code>
          </pre>
          <h3 id="rc">Next version (currently in development)</h3>
          <p>
            See <a href={`${siteConfig.baseUrl}${siteConfig.docsUrl}/${props.language}/next/getting-started.html`}>documentation</a> or go directly to{' '}
            <a href={`${siteConfig.baseUrl}${siteConfig.docsUrl}/${props.language}/next/commands.html`}>commands</a> reference.
          </p>
          <p>
            Install with:
          </p>
          <pre>
            <code className="hljs langiage-shell">npm install -g @esy-nightly/esy</code>
          </pre>
          <h3 id="archive">Past Versions</h3>
          <table className="versions">
            <tbody>
              {versions.map(
                version =>
                  version !== latestVersion && (
                    <tr key={version}>
                      <th>{version}</th>
                      <td>
                        <a href={`/docs/en/${version}/gettings-started.html`}>Documentation</a>
                      </td>
                      <td>
                        <a href={`https://github.com/esy/esy/blob/master/CHANGELOG.md#${version.replace(/\./g, '')}--latest`}>Release Notes</a>
                      </td>
                    </tr>
                  ),
              )}
            </tbody>
          </table>
          <p>
            You can find past versions of this project on{' '}
            <a href={repoUrl}>GitHub</a>.
          </p>
        </div>
      </Container>
    </div>
  );
}

module.exports = Versions;
