#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const DEV = process.env.ESY_DEV || !fs.existsSync(path.join(__dirname, '..', 'lib'));

if (DEV) {
  require('babel-register');
  require('../src/bin/esy');
} else {
  require('../lib/bin/esy');
}
