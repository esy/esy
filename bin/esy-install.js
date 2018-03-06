#!/usr/bin/env node
// @noflow

var fs = require('fs');
var path = require('path');

var root = path.join(__dirname, '..', 'esy-install');
var entryPoint = path.join(root, 'src', 'bin', 'esy.js');

const node_modules = path.join(root, 'node_modules');
const esy_install_node_modules = path.join(root, 'esy-install', 'node_modules');
require('../esy-install/node_modules/babel-register')({
  ignore: filename => {
    const ignore =
      filename.startsWith(node_modules) ||
      filename.startsWith(esy_install_node_modules);
    return ignore;
  },
});
require(entryPoint);
