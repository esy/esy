#!/usr/bin/env node
// @noflow

var fs = require('fs');
var path = require('path');

var SRC = path.join(__dirname, '..', 'src', 'bin', 'esy.js');
var LIB = path.join(__dirname, '..', 'lib', 'bin', 'esy.js');

if (fs.existsSync(SRC)) {
  require('babel-register');
  require(SRC);
} else {
  require(LIB);
}
