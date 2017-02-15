'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _extends = Object.assign || function (target) { for (var i = 1; i < arguments.length; i++) { var source = arguments[i]; for (var key in source) { if (Object.prototype.hasOwnProperty.call(source, key)) { target[key] = source[key]; } } } return target; };

let applyPatch = (() => {
  var _ref4 = _asyncToGenerator(function* (packageJson, target) {
    if (packageJson.opam.patch) {
      const patchFilename = _path2.default.join(target, '_esy_patch');
      yield _fs2.default.writeFile(patchFilename, packageJson.opam.patch, 'utf8');
      yield _execa2.default.shell('patch -p1 < _esy_patch', { cwd: target });
    }
  });

  return function applyPatch(_x8, _x9) {
    return _ref4.apply(this, arguments);
  };
})();

let putFiles = (() => {
  var _ref5 = _asyncToGenerator(function* (packageJson, target) {
    if (packageJson.opam.files) {
      yield Promise.all(packageJson.opam.files.map(function (file) {
        return _fs2.default.writeFile(_path2.default.join(target, file.name), file.content, 'utf8');
      }));
    }
  });

  return function putFiles(_x10, _x11) {
    return _ref5.apply(this, arguments);
  };
})();

let readJson = (() => {
  var _ref6 = _asyncToGenerator(function* (filename) {
    const data = yield _fs2.default.readFile(filename, 'utf8');
    const value = JSON.parse(data);
    return value;
  });

  return function readJson(_x12) {
    return _ref6.apply(this, arguments);
  };
})();

let writeJson = (() => {
  var _ref7 = _asyncToGenerator(function* (filename, value) {
    const data = JSON.stringify(value, null, 2);
    yield _fs2.default.writeFile(filename, data, 'utf8');
  });

  return function writeJson(_x13, _x14) {
    return _ref7.apply(this, arguments);
  };
})();

let lookupPackageCollection = (() => {
  var _ref8 = _asyncToGenerator(function* (packageName) {
    const packageRecordFilename = _path2.default.join(OPAM_METADATA_STORE, `${packageName}.json`);

    if (!(yield _fs2.default.exists(packageRecordFilename))) {
      throw new Error(`No package found: @opam-alpha/${packageName}`);
    }

    return readJson(packageRecordFilename);
  });

  return function lookupPackageCollection(_x15) {
    return _ref8.apply(this, arguments);
  };
})();

let fetchFromOpam = (() => {
  var _ref9 = _asyncToGenerator(function* (target, resolution, fetcher) {
    if (resolution.tarball === 'empty') {
      yield (0, _mkdirpThen2.default)(target);
    } else {
      const basename = _path2.default.basename(resolution.tarball);
      const stage = (0, _tempfile2.default)(basename);

      yield (0, _mkdirpThen2.default)(stage);
      yield (0, _mkdirpThen2.default)(target);

      const filename = _path2.default.join(stage, basename);
      const stream = yield fetcher.getStream(resolution.tarball);
      yield saveStreamToFile(stream, filename, resolution.checksum);
      yield unpackTarball(filename, target);
    }
  });

  return function fetchFromOpam(_x16, _x17, _x18) {
    return _ref9.apply(this, arguments);
  };
})();

let saveStreamToFile = (() => {
  var _ref10 = _asyncToGenerator(function* (stream, filename, md5checksum = null) {
    let hasher = _crypto2.default.createHash('md5');
    return new Promise(function (resolve, reject) {
      let out = _fs2.default.createWriteStream(filename);
      stream.on('data', function (chunk) {
        if (md5checksum != null) {
          hasher.update(chunk);
        }
      }).pipe(out).on('error', function (err) {
        reject(err);
      }).on('finish', function () {
        let actualChecksum = hasher.digest('hex');
        if (md5checksum != null) {
          if (actualChecksum !== md5checksum) {
            reject(new Error(`Incorrect md5sum (expected ${md5checksum}, got ${actualChecksum})`));
            return;
          }
        }
        resolve();
      });
      if (stream.resume) {
        stream.resume();
      }
    });
  });

  return function saveStreamToFile(_x19, _x20) {
    return _ref10.apply(this, arguments);
  };
})();

let unpackTarball = (() => {
  var _ref11 = _asyncToGenerator(function* (filename, target) {
    let isGzip = filename.endsWith('.tar.gz') || filename.endsWith('.tgz');
    let isBzip2 = filename.endsWith('.tbz') || filename.endsWith('.tar.bz2');
    if (!isGzip && !isBzip2) {
      throw new Error(`unknown tarball type: ${filename}`);
    }
    yield (0, _execa2.default)('tar', ['-x', isGzip ? '-z' : '-j', '-f', filename, '--strip-components', '1', '-C', target]);
  });

  return function unpackTarball(_x21, _x22) {
    return _ref11.apply(this, arguments);
  };
})();

let resolveFromOpam = (() => {
  var _ref12 = _asyncToGenerator(function* (spec, opts) {
    let [_opamScope, packageName] = spec.name.split('/');
    let packageCollection = yield lookupPackageCollection(packageName);
    let packageJson = resolveVersion(packageCollection, spec);
    let opamInfo = packageJson.opam;
    if (opamInfo.url) {
      let id = `${packageName}#${(0, _Utility.hash)(opamInfo.url + (0, _Utility.hash)(JSON.stringify(packageJson)))}`;
      let resolution = {
        type: 'tarball',
        id,
        tarball: opamInfo.url,
        checksum: opamInfo.checksum || null,
        opam: { name: packageName, version: packageJson.version }
      };
      return { resolution };
    } else {
      let id = `${packageName}#${(0, _Utility.hash)(JSON.stringify(packageJson))}`;
      let resolution = {
        type: 'tarball',
        id,
        tarball: 'empty',
        opam: { name: packageName, version: packageJson.version }
      };
      return { resolution };
    }
  });

  return function resolveFromOpam(_x23, _x24) {
    return _ref12.apply(this, arguments);
  };
})();

/**
 * Resolve version from a package collection given a package spec.
 */


exports.esyInstallCommand = esyInstallCommand;
exports.esyAddCommand = esyAddCommand;

var _os = require('os');

var _path = require('path');

var _path2 = _interopRequireDefault(_path);

var _crypto = require('crypto');

var _crypto2 = _interopRequireDefault(_crypto);

var _fs = require('mz/fs');

var _fs2 = _interopRequireDefault(_fs);

var _execa = require('execa');

var _execa2 = _interopRequireDefault(_execa);

var _semver = require('semver');

var _semver2 = _interopRequireDefault(_semver);

var _tempfile = require('tempfile');

var _tempfile2 = _interopRequireDefault(_tempfile);

var _chalk = require('chalk');

var _chalk2 = _interopRequireDefault(_chalk);

var _ndjson = require('ndjson');

var _ndjson2 = _interopRequireDefault(_ndjson);

var _bole = require('bole');

var _bole2 = _interopRequireDefault(_bole);

var _mkdirpThen = require('mkdirp-then');

var _mkdirpThen2 = _interopRequireDefault(_mkdirpThen);

var _pnpm = require('@andreypopp/pnpm');

var pnpm = _interopRequireWildcard(_pnpm);

var _Utility = require('../Utility');

var _logger = require('./logger');

var _logger2 = _interopRequireDefault(_logger);

function _interopRequireWildcard(obj) { if (obj && obj.__esModule) { return obj; } else { var newObj = {}; if (obj != null) { for (var key in obj) { if (Object.prototype.hasOwnProperty.call(obj, key)) newObj[key] = obj[key]; } } newObj.default = obj; return newObj; } }

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function _asyncToGenerator(fn) { return function () { var gen = fn.apply(this, arguments); return new Promise(function (resolve, reject) { function step(key, arg) { try { var info = gen[key](arg); var value = info.value; } catch (error) { reject(error); return; } if (info.done) { resolve(value); } else { return Promise.resolve(value).then(function (value) { step("next", value); }, function (err) { step("throw", err); }); } } return step("next"); }); }; }

const OPAM_METADATA_STORE = _path2.default.join(__dirname, '..', '..', 'opam-packages');

const USER_HOME = process.env.HOME;

const STORE_PATH = process.env.ESY__STORE != null ? _path2.default.join(process.env.ESY__STORE, '_fetch') : _path2.default.join(USER_HOME, '.esy', '_fetch');

const installationSpec = {

  storePath: STORE_PATH,
  preserveSymlinks: false,
  lifecycle: {

    packageWillResolve: (() => {
      var _ref = _asyncToGenerator(function* (spec, opts) {
        switch (spec.type) {
          case 'range':
          case 'version':
          case 'tag':
            {
              if (spec.scope === '@opam-alpha') {
                return resolveFromOpam(spec, opts);
              }
            }
        }
        // fallback to pnpm's resolution algo
        return null;
      });

      return function packageWillResolve(_x, _x2) {
        return _ref.apply(this, arguments);
      };
    })(),

    packageWillFetch: (() => {
      var _ref2 = _asyncToGenerator(function* (target, resolution, opts) {
        if (resolution.opam == null) {
          // fallback to pnpm's fetching algo
          return false;
        } else {
          yield fetchFromOpam(target, resolution, opts.got);
          return true;
        }
      });

      return function packageWillFetch(_x3, _x4, _x5) {
        return _ref2.apply(this, arguments);
      };
    })(),

    packageDidFetch: (() => {
      var _ref3 = _asyncToGenerator(function* (target, resolution) {
        const packageJsonFilename = _path2.default.join(target, 'package.json');

        if (resolution.opam == null) {
          let packageJson = yield readJson(packageJsonFilename);
          packageJson = _extends({}, packageJson, { _resolved: resolution.id });
          yield writeJson(packageJsonFilename, packageJson);
        } else {
          const { name, version } = resolution.opam;
          const packageCollection = yield lookupPackageCollection(name);

          let packageJson = packageCollection.versions[version];
          packageJson = _extends({}, packageJson, { _resolved: resolution.id });
          writeJson(packageJsonFilename, packageJson);

          yield putFiles(packageJson, target);
          yield applyPatch(packageJson, target);
        }
      });

      return function packageDidFetch(_x6, _x7) {
        return _ref3.apply(this, arguments);
      };
    })()
  }
};

function resolveVersion(packageCollection, spec) {
  const versions = Object.keys(packageCollection.versions);

  if (spec.type === 'tag') {
    // Only allow "latest" tag
    if (spec.spec !== 'latest') {
      throw new Error(`No compatible version found: ${spec.raw}`);
    }
    const maxVersion = _semver2.default.maxSatisfying(versions, '*', true);
    return packageCollection.versions[maxVersion];
  } else {
    const maxVersion = _semver2.default.maxSatisfying(versions, spec.spec, true);
    if (maxVersion == null) {
      throw new Error(`No compatible version found: ${spec.raw}`);
    }
    return packageCollection.versions[maxVersion];
  }
}

function initLogging() {
  let streamParser = _ndjson2.default.parse();
  (0, _logger2.default)(streamParser);
  _bole2.default.output([{ level: 'debug', stream: streamParser }]);
}

function esyInstallCommand() {
  // This is set during installation so that postinstall scripts can
  // be made to work with *either* npm or esy. You still need to create
  // an `esy` && `esy.build` section in your `package.json`.
  // "postinstall": "if [ $esy__installing != '' ]; then exit 0; fi && ..."
  process.env['esy__installing'] = '1';
  initLogging();
  pnpm.install(installationSpec).then(() => {
    console.log(_chalk2.default.green('*** installation finished'));
  }, err => {
    console.error(_chalk2.default.red(err.stack || err));
    process.exit(1);
  });
}

function esyAddCommand(...installPackages) {
  initLogging();
  pnpm.installPkgs(installPackages, _extends({}, installationSpec, {
    save: true
  })).then(() => {
    console.log(_chalk2.default.green('*** installation finished'));
  }, err => {
    console.error(_chalk2.default.red(err.stack || err));
    process.exit(1);
  });
}
