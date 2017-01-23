let fs = require('fs');

let packageJsonFilename = require.resolve('../package.json');
let packageJson = require('../package.json');

let dependencies = packageJson['dependencies'];
let scripts = packageJson['scripts'];

delete packageJson['dependencies'];
delete packageJson['scripts'];

packageJson['__dependencies'] = dependencies;
packageJson['__scripts'] = scripts;

fs.writeFileSync(packageJsonFilename, JSON.stringify(packageJson, null, 2), 'utf8');
