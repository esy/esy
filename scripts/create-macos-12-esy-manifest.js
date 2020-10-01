const fs = require ('fs');
const path = require ('path');
let esyJson = require ("../esy.json");

esyJson.esy.buildEnv = { "MACOSX_DEPLOYMENT_TARGET": "10.12" }
fs.writeFileSync ("../esy.json", JSON.stringify (esyJson, null, 2));
