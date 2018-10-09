// @flow

const os = require('os');
const outdent = require('outdent');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows('Needs investigation');

function makeFixture(p) {
  return [
    helpers.packageJson({
      name: 'hasBuildTimeDeps',
      version: '1.0.0',
      esy: {
        buildsInSource: true,
        build: ['buildTimeDep.cmd #{self.name}'],
        install: ['cp #{self.name}.cmd #{self.bin / self.name}.cmd'],
      },
      dependencies: {
        dep: '*',
      },
      buildTimeDependencies: {
        buildTimeDep: '*',
      },
    }),
    helpers.dir(
      'node_modules',
      helpers.dir(
        'buildTimeDep',
        helpers.packageJson({
          name: 'buildTimeDep',
          version: '1.0.0',
          esy: {
            buildsInSource: true,
            build: [helpers.buildCommand(p, '#{self.name}.js')],
            install: [
              'cp #{self.name}.cmd #{self.bin / self.name}.cmd',
              'cp #{self.name}.js #{self.bin / self.name}.js',
            ],
          },
          '_esy.source': 'path:./',
        }),
        helpers.file(
          'buildTimeDep.js',
          outdent`
          var name = process.argv[2];
          var source = \`
          console.log("Built with buildTimeDep@1.0.0");
          console.log("__" + \${JSON.stringify(name)} + "__");
          \`;

          const path = require('path');
          const fs = require('fs');
          const isWindows = process.platform === 'win32';

          const script = path.join(process.cwd(), name + '.js');
          const output = path.join(process.cwd(), name + '.cmd');

          fs.writeFileSync(script, source);
          if (isWindows) {
            fs.writeFileSync(
              output,
              \`@${JSON.stringify(process.execPath)} \${JSON.stringify(script)} %*\`
            );
          } else {
            fs.writeFileSync(
              output,
              \`#!${process.execPath}
              require(\${JSON.stringify(script)})
              \`
            );
            fs.chmodSync(output, 0755);
          }
        `,
        ),
      ),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            buildsInSource: true,
            build: ['buildTimeDep.cmd #{self.name}'],
            install: ['cp #{self.name}.cmd #{self.bin / self.name}.cmd'],
          },
          buildTimeDependencies: {
            buildTimeDep: '*',
          },
          '_esy.source': 'path:./',
        }),
        helpers.dir(
          'node_modules',
          helpers.dir(
            'buildTimeDep',
            helpers.packageJson({
              name: 'buildTimeDep',
              version: '2.0.0',
              esy: {
                buildsInSource: true,
                build: [helpers.buildCommand(p, '#{self.name}.js')],
                install: [
                  'cp #{self.name}.cmd #{self.bin / self.name}.cmd',
                  'cp #{self.name}.js #{self.bin / self.name}.js',
                ],
              },
              '_esy.source': 'path:./',
            }),
            helpers.file(
              'buildTimeDep.js',
              outdent`
              var name = process.argv[2];
              var source = \`
              console.log("Built with buildTimeDep@2.0.0");
              console.log("__" + \${JSON.stringify(name)} + "__");
              \`;

              const path = require('path');
              const fs = require('fs');
              const isWindows = process.platform === 'win32';

              const script = path.join(process.cwd(), name + '.js');
              const output = path.join(process.cwd(), name + '.cmd');

              fs.writeFileSync(script, source);
              if (isWindows) {
                fs.writeFileSync(
                  output,
                  \`@${JSON.stringify(process.execPath)} \${JSON.stringify(script)} %*\`
                );
              } else {
                fs.writeFileSync(
                  output,
                  \`#!${process.execPath}
                  require(\${JSON.stringify(script)})
                  \`
                );
                fs.chmodSync(output, 0755);
              }
            `,
            ),
          ),
        ),
      ),
    ),
  ];
}

test.skip('Build project and dep with different version of the same buildTimeDep', async () => {
  const p = await helpers.createTestSandbox();
  await p.fixture(...makeFixture(p));
  await p.esy('build');

  {
    const {stdout} = await p.esy('x hasBuildTimeDeps.cmd');
    expect(stdout.trim()).toEqual(
      'Built with buildTimeDep@1.0.0' + os.EOL + '__hasBuildTimeDeps__',
    );
  }

  {
    const {stdout} = await p.esy('dep.cmd');
    expect(stdout.trim()).toEqual('Built with buildTimeDep@2.0.0' + os.EOL + '__dep__');
  }
});
