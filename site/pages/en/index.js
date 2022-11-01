const React = require('react');

const CompLibrary = require('../../core/CompLibrary.js');
const MarkdownBlock = CompLibrary.MarkdownBlock; /* Used to read markdown */
const Container = CompLibrary.Container;
const GridBlock = CompLibrary.GridBlock;

const translate = require('../../server/translate.js').translate;

const siteConfig = require(process.cwd() + '/siteConfig.js');

class Button extends React.Component {
  render() {
    return (
      <div className="pluginWrapper">
        <a
          className={`button ${this.props.className || ''}`}
          href={this.props.href}
          target={this.props.target}>
          {this.props.children}
        </a>
      </div>
    );
  }
}

Button.defaultProps = {
  target: '_self',
};
const pre = '```';
const code = '`';

const quickStart = `${pre}bash
% npm install -g esy

# Clone example, install dependencies, then build
% git clone https://github.com/esy-ocaml/hello-reason.git
% cd hello-reason
% esy
${pre}`;

class HomeSplash extends React.Component {
  render() {
    let promoSection = (
      <div className="section promoSection">
        <div className="promoRow">
          <div className="pluginRowBlock">
            <Button
              className="getStarted"
              href={
                siteConfig.baseUrl +
                'docs/' +
                this.props.language +
                '/getting-started.html'
              }>
              <translate>Get Started</translate>
            </Button>
            <Button
              href={
                siteConfig.baseUrl + 'docs/' + this.props.language + '/how-it-works.html'
              }>
              How it works
            </Button>
          </div>
        </div>
      </div>
    );

    return (
      <div className="homeContainer">
        <div className="homeWrapperWrapper">
          <div className="wrapper homeWrapper">
            <div className="homeWrapperInner">
              <img
                width={150}
                height={150}
                src={siteConfig.baseUrl + 'img/block-red.svg'}
              />
              <div>
                <div className="projectTitle">{siteConfig.title}</div>
                <div className="homeTagLine">{siteConfig.tagline}</div>
                {promoSection}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }
}

class Index extends React.Component {
  render() {
    let language = this.props.language || 'en';

    return (
      <div>
        <HomeSplash language={language} />
        <div className="mainContainer">
          <Container className="homeThreePoints" padding={['bottom']}>
            <GridBlock
              align="center"
              contents={[
                {
                  title: '`package.json` Driven',
                  content: '**Familiar** `npm` inspired dependency management.',
                },
                {
                  title: 'Project Isolation',
                  content:
                    'Develop **multiple projects** simultaneously without conflict.',
                },
                {
                  title: 'Fast, Teleporting Builds',
                  content:
                    'All local projects automatically share **build caches** with each-other and caches support **teleportation** across network.',
                },
                {
                  title: 'Deterministic and Offline',
                  content:
                    'Generate **lock** files and dependency source **snapshots** for ultra-reliable, corporate-friendly builds. Network optional.',
                },
              ]}
              layout="fourColumn"
            />
          </Container>
          <Container
            background="light"
            className="paddingBottom quickStartAndExamples homeCodeSnippet">
            <div>
              <h2>Quick Start</h2>
              <MarkdownBlock>{quickStart}</MarkdownBlock>
            </div>
          </Container>
        </div>
      </div>
    );
  }
}

module.exports = Index;
