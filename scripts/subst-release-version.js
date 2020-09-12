const fs = require ('fs');
const path = require ('path');
let {name, version} = require ("../esy.json");


let pkgJson = path.join (process.cwd (), 'release', 'package.json');
const pkgJsonData = JSON.parse (fs.readFileSync (pkgJson, 'utf8'));
pkgJsonData.name = name;
pkgJsonData.version = version;
fs.writeFileSync (pkgJson, JSON.stringify (pkgJsonData, null, 2));
