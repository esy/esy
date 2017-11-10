#!/usr/bin/env node
// @noflow

var fs = require('fs');
var path = require('path');

var SRC = path.join(__dirname, '..', 'src', 'bin', 'esy.js');
var LIB = path.join(__dirname, '..', 'lib', 'bin', 'esy.js');

if (fs.existsSync(SRC)) {
  const root = path.dirname(__dirname);
  const node_modules = path.join(root, 'node_modules');
  const esy_install_node_modules = path.join(root, 'esy-install', 'node_modules');
  require('babel-register')({
    ignore: filename => {
      const ignore =
        filename.startsWith(node_modules) ||
        filename.startsWith(esy_install_node_modules);
      return ignore;
    },
  });
  require(SRC);
} else {
  require(LIB);
}
