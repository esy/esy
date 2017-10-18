#!/usr/bin/env node
/* eslint-disable */

const webpack = require('webpack');
const path = require('path');
const util = require('util');
const fs = require('fs');

const version = require('../package.json').version;
const basedir = path.join(__dirname, '../');
const babelRc = JSON.parse(fs.readFileSync(path.join(basedir, '.babelrc'), 'utf8'));
const babelPluginTrasnformFsReadFileSync = require.resolve(
  './babel-plugin-transform-fs-read-file-sync.js',
);

babelRc.plugins.unshift(babelPluginTrasnformFsReadFileSync);

const output = process.argv[2];
if (output == null) {
  console.log(`error: provide output filename as an argument`);
  process.exit(1);
}

// Use the real node __dirname and __filename in order to get Yarn's source
// files on the user's system. See constants.js
const nodeOptions = {
  __filename: false,
  __dirname: false,
};

// We need to exclude @esy-opam/esy-ocaml bundle b/c of lincesing concerns.
// Note that we also need both commonjs and commonjs2 configurations due to a
// bug in webpack.
const externals = {
  '@esy-ocaml/esy-opam': {
    commonjs: '@esy-ocaml/esy-opam',
    commonjs2: '@esy-ocaml/esy-opam',
  },
};

//
// Modern build
//

const compiler = webpack({
  // devtool: 'inline-source-map',
  entry: {
    [`${output}/esy.js`]: path.join(basedir, 'src/bin/esy.js'),
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: {
          loader: 'babel-loader',
          options: babelRc,
        },
      },
    ],
  },
  plugins: [
    new webpack.BannerPlugin({
      banner: '#!/usr/bin/env node',
      raw: true,
    }),
  ],
  output: {
    filename: `[name]`,
    path: basedir,
    libraryTarget: 'commonjs2',
  },
  externals: externals,
  target: 'node',
  node: nodeOptions,
});

compiler.run((err, stats) => {
  if (err) {
    throw err;
  }
  if (stats.compilation.errors.length > 0) {
    for (const error of stats.compilation.errors) {
      console.log(error);
    }
    process.exit(1);
  }
  const fileDependencies = stats.compilation.fileDependencies;
  const filenames = fileDependencies.map(x => x.replace(basedir, ''));
  console.log(util.inspect(filenames, {maxArrayLength: null}));
});
