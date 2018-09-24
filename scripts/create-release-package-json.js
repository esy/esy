let esyJson = require('../package.json');

console.log(
  JSON.stringify({
    name: esyJson.name,
    version: esyJson.version,
    license: esyJson.license,
    description: esyJson.description,
    repository: esyJson.repository,
    dependencies: {
      "@esy-ocaml/esy-opam": "0.0.15",
      "esy-solve-cudf": esyJson.dependencies["esy-solve-cudf"]
    },
    scripts: {
      postinstall: "node ./postinstall.js"
    },
    bin: {
      esy: "_build/default/esy/bin/esyCommand.exe"
    },
    files: [
      "bin/",
      "postinstall.js",
      "platform-linux/",
      "platform-darwin/",
      "platform-windows-x64/",
      "_build/default/**/*.exe"
    ]
  }, null, 2)
);
