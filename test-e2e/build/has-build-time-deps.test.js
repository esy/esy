// @flow

const os = require('os');
const outdent = require('outdent');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows('Needs investigation');

const fixture = [
  helpers.packageJson({
    name: 'hasBuildTimeDeps',
    version: '1.0.0',
    esy: {
      buildsInSource: true,
      build: ['buildTimeDep.exe #{self.name}', 'chmod +x #{self.name}.exe'],
      install: ['cp #{self.name}.exe #{self.bin / self.name}.exe'],
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
          build: 'chmod +x #{self.name}.exe',
          install: 'cp #{self.name}.exe #{self.bin / self.name}.exe',
        },
        '_esy.source': 'path:./',
      }),
      helpers.file(
        'buildTimeDep.exe',
        outdent`
          #!${process.execPath}

          var name = process.argv[2];
          var source = \`#!${process.execPath}

          console.log("Built with buildTimeDep@1.0.0");
          console.log("__" + \${JSON.stringify(name)} + "__");
          \`;

          require('fs').writeFileSync(name + ".exe", source);
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
          build: ['buildTimeDep.exe #{self.name}', 'chmod +x #{self.name}.exe'],
          install: ['cp #{self.name}.exe #{self.bin / self.name}.exe'],
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
              build: 'chmod +x #{self.name}.exe',
              install: 'cp #{self.name}.exe #{self.bin / self.name}.exe',
            },
            '_esy.source': 'path:./',
          }),
          helpers.file(
            'buildTimeDep.exe',
            outdent`
              #!${process.execPath}

              var name = process.argv[2];
              var source = \`#!${process.execPath}

              console.log("Built with buildTimeDep@2.0.0");
              console.log("__" + \${JSON.stringify(name)} + "__");
              \`;

              require('fs').writeFileSync(name + ".exe", source);
            `,
          ),
        ),
      ),
    ),
  ),
];

test('Build project and dep with different version of the same buildTimeDep', async () => {
  const p = await helpers.createTestSandbox(...fixture);
  await p.esy('build');

  {
    const {stdout} = await p.esy('x hasBuildTimeDeps.exe');
    expect(stdout.trim()).toEqual(
      'Built with buildTimeDep@1.0.0' + os.EOL + '__hasBuildTimeDeps__',
    );
  }

  {
    const {stdout} = await p.esy('dep.exe');
    expect(stdout.trim()).toEqual('Built with buildTimeDep@2.0.0' + os.EOL + '__dep__');
  }
});
