let esyJson = require('../esy.json');
let packageJson = require('../package.json');

let version = esyJson.version;

if (process.env.ESY__RELEASE_VERSION_COMMIT != null) {
  version = version + '-' + process.env.ESY__RELEASE_VERSION_COMMIT.slice(0, 6);
}

console.log(
  JSON.stringify(
    {
      name: esyJson.name,
      version: version,
      license: esyJson.license,
      description: esyJson.description,
      repository: esyJson.repository,
      dependencies: {
        'esy-solve-cudf': packageJson.devDependencies['esy-solve-cudf']
      },
      scripts: {
        postinstall: 'node ./postinstall.js'
      },
      bin: {
        esy: '_build/default/bin/esy.exe'
      },
      files: [
        'bin/',
        'postinstall.js',
        'platform-linux/',
        'platform-darwin/',
        'platform-win32/',
        '_build/default/**/*.exe'
      ]
    },
    null,
    2
  )
);
