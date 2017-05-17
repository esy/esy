#!/usr/bin/env node
// @noflow

var fs = require('fs');
var path = require('path');

var SRC = path.join(__dirname, '..', 'src', 'bin', 'esybuild.js');
var LIB = path.join(__dirname, '..', 'lib', 'bin', 'esybuild.js');

if (fs.existsSync(SRC)) {
  require('babel-register');
  require(SRC);
} else {
  require(LIB);
}
