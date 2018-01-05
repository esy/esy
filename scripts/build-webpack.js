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

const input = process.argv[2];
const output = process.argv[3];

if (output == null || input == null) {
  console.log(`error: node build-webpack.js <input> <output>`);
  process.exit(1);
}

// Use the real node __dirname and __filename in order to get Yarn's source
// files on the user's system. See constants.js
const nodeOptions = {
  __filename: false,
  __dirname: false,
};

// Note that we also need both commonjs and commonjs2 configurations due to a
// bug in webpack.
const externals = {
  // Exclude @esy-opam/esy-ocaml from bundle b/c of lincesing concerns.
  '@esy-ocaml/esy-opam': {
    commonjs: '@esy-ocaml/esy-opam',
    commonjs2: '@esy-ocaml/esy-opam',
  },
  // Exclude @esy-opam/ocamlrun b/c it's a binary.
  '@esy-ocaml/ocamlrun': {
    commonjs: '@esy-ocaml/ocamlrun',
    commonjs2: '@esy-ocaml/ocamlrun',
  },
  // Exclude fastreplacestring b/c it's a binary.
  fastreplacestring: {
    commonjs: 'fastreplacestring',
    commonjs2: 'fastreplacestring',
  },
};

const compiler = webpack({
  // devtool: 'inline-source-map',
  entry: {
    [output]: input,
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
