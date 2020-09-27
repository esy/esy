/**
 * Esy npm release installation script.
 *
 * This is made to be invoked from npm's postinstall hook:
 *
 *   node esyInstallRelease.js
 *
 * Note that it's important to keep this program as portable as possible and not
 * to use any of the non-standard JS features.
 */

require('@babel/polyfill');
var path = require('path');
var fs = require('fs');
var os = require('os');
var promisepipe = require('promisepipe');
var tarFs = require('tar-fs');
var gunzipMaybe = require('gunzip-maybe');

/**
 * Constants
 */

var STORE_BUILD_TREE = 'b';
var STORE_INSTALL_TREE = 'i';
var STORE_STAGE_TREE = 's';
var ESY_STORE_VERSION = 3;
var MAX_SHEBANG_LENGTH = 127;
var OCAMLRUN_STORE_PATH = 'ocaml-n.00.0000-########/bin/ocamlrun';
var ESY_STORE_PADDING_LENGTH =
  MAX_SHEBANG_LENGTH -
  '!#'.length -
  ('/' + STORE_INSTALL_TREE + '/' + OCAMLRUN_STORE_PATH).length;

var shouldRewritePrefix = process.env.ESY_RELEASE_REWRITE_PREFIX === 'true';

/**
 * Utils
 */

function info(msg) {
  console.log(msg);
}

function error(err) {
  if (err instanceof Error) {
    console.error('error: ' + err.stack);
  } else {
    console.error('error: ' + err);
  }
  process.exit(1);
}

function promisify(fn, firstData) {
  return function() {
    var args = Array.prototype.slice.call(arguments);
    return new Promise(function(resolve, reject) {
      args.push(function() {
        var args = Array.prototype.slice.call(arguments);
        var err = args.shift();
        var res = args;

        if (res.length <= 1) {
          res = res[0];
        }

        if (firstData) {
          res = err;
          err = null;
        }

        if (err) {
          reject(err);
        } else {
          resolve(res);
        }
      });

      fn.apply(null, args);
    });
  };
}

function processWithConcurrencyLimit(tasks, process, concurrency) {
  tasks = tasks.slice(0);
  return new Promise(function(resolve, reject) {
    var inprogress = 0;
    var rejected = false;

    function run() {
      if (tasks.length === 0) {
        if (inprogress === 0) {
          resolve();
        }
        return;
      }

      while (inprogress < concurrency && tasks.length > 0) {
        var task = tasks.pop();
        inprogress = inprogress + 1;
        process(task).then(
          function() {
            if (!rejected) {
              inprogress = inprogress - 1;
              run();
            }
          },
          function(err) {
            if (!rejected) {
              rejected = true;
              reject(err);
            }
          }
        );
      }
    }

    run();
  });
}

/**
 * Filesystem functions.
 */

var fsExists = promisify(fs.exists, true);
var fsReaddir = promisify(fs.readdir);
var fsReadFile = promisify(fs.readFile);
var fsWriteFile = promisify(fs.writeFile);
var fsSymlink = promisify(fs.symlink);
var fsUnlink = promisify(fs.unlink);
var fsReadlink = promisify(fs.readlink);
var fsStat = promisify(fs.stat);
var fsLstat = promisify(fs.lstat);
var fsMkdir = promisify(fs.mkdir);
var fsRename = promisify(fs.rename);

function fsWalk(dir, relativeDir) {
  var files = [];

  return fsReaddir(dir).then(function(filenames) {
    function process(name) {
      var relative = relativeDir ? path.join(relativeDir, name) : name;
      var loc = path.join(dir, name);
      return fsLstat(loc).then(function(stats) {
        files.push({
          relative,
          basename: name,
          absolute: loc,
          mtime: +stats.mtime,
          stats
        });

        if (stats.isDirectory()) {
          return fsWalk(loc, relative).then(function(nextFiles) {
            files = files.concat(nextFiles);
          });
        }
      });
    }

    return processWithConcurrencyLimit(filenames, process, 20).then(function() {
      return files;
    });
  });
}

/**
 * Store utils
 */

function getStorePathForPrefix(prefix) {
  var prefixLength = path.join(prefix, String(ESY_STORE_VERSION)).length;
  var paddingLength = ESY_STORE_PADDING_LENGTH - prefixLength;
  if (paddingLength < 0) {
    error(
      "Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts"
    );
  }
  var p = path.join(prefix, String(ESY_STORE_VERSION));
  while (p.length < ESY_STORE_PADDING_LENGTH) {
    p = p + '_';
  }
  return p;
}

var cwd = process.cwd();
var releasePackagePath = cwd;
var releaseExportPath = path.join(releasePackagePath, '_export');
var releaseBinPath = path.join(releasePackagePath, 'bin');
var unpaddedStorePath = path.join(releasePackagePath, String(ESY_STORE_VERSION));

/**
 * Main
 */

async function importBuild(filename, storePath) {
  var buildId = path.basename(filename).replace(/\.tar\.gz$/g, '');

  info('importing: ' + buildId);

  async function extractTarball(storeStagePath) {
    await promisepipe(
      fs.createReadStream(filename),
      gunzipMaybe(),
      tarFs.extract(storeStagePath)
    );
  }

  if (storePath != null) {
    var storeStagePath = path.join(storePath, STORE_STAGE_TREE);
    var buildStagePath = path.join(storeStagePath, buildId);
    var buildFinalPath = path.join(storePath, STORE_INSTALL_TREE, buildId);

    await fsMkdir(buildStagePath);
    await extractTarball(storeStagePath);

    // We try to rewrite path prefix inside a stage path and then transactionally
    // mv to the final path
    let prevStorePrefix = await fsReadFile(path.join(buildStagePath, '_esy', 'storePrefix'));
    prevStorePrefix = prevStorePrefix.toString();
    await rewritePaths(buildStagePath, prevStorePrefix, storePath);
    await fsRename(buildStagePath, buildFinalPath);
  } else {
    var storeStagePath = path.join(unpaddedStorePath, STORE_STAGE_TREE);
    var buildStagePath = path.join(storeStagePath, buildId);
    var buildFinalPath = path.join(unpaddedStorePath, STORE_INSTALL_TREE, buildId);
    await fsMkdir(buildStagePath);
    await extractTarball(storeStagePath);
    await fsRename(buildStagePath, buildFinalPath);
  }
}

function rewritePaths(path, from, to) {
  var concurrency = 20;

  function process(file) {
    if (file.stats.isSymbolicLink()) {
      return rewritePathInSymlink(file.absolute, from, to);
    } else {
      return rewritePathInFile(file.absolute, from, to);
    }
  }

  return fsWalk(path).then(function(files) {
    return processWithConcurrencyLimit(files, process, concurrency);
  });
}

function rewritePathInFile(filename, origPath, destPath) {
  return fsStat(filename).then(function(stat) {
    if (!stat.isFile()) {
      return;
    }

    function subst(content, origPath, destPath) {
      var offset = content.indexOf(origPath);
      var needRewrite = offset > -1;
      while (offset > -1) {
        content.write(destPath, offset);
        offset = content.indexOf(origPath);
      }
      return needRewrite;
    }

    const allFwd = s => s.replace(/\\/g, '/');
    const allBack = s => s.replace(/\//g, '\\');
    const allButFirstFwd = s => {
      let parts = allFwd(s).split('/');
      if (parts.length === 0) {
	return "";
      } else {
	return parts[0] + '/' + parts.slice(1).join('\\')
      }
    };
    const allDouble = s => allFwd(s).replace(/\/\//g, '\\\\');
    return fsReadFile(filename).then(function(content) {
      let r1 = subst(content, allFwd(origPath), allFwd(destPath));
      let r2 = subst(content, allBack(origPath), allBack(destPath));
      let r3 = subst(content, allButFirstFwd(origPath), allButFirstFwd(destPath));
      let r4 = subst(content, allDouble(origPath), allDouble(destPath));
      if (r1 || r2 || r3 || r4) {
        return fsWriteFile(filename, content);
      }
    });
  });
}

function rewritePathInSymlink(filename, origPath, destPath) {
  return fsLstat(filename).then(function(stat) {
    if (!stat.isSymbolicLink()) {
      return;
    }
    return fsReadlink(filename).then(function(linkPath) {
      if (linkPath.indexOf(origPath) !== 0) {
        return;
      }
      var nextTargetPath = path.join(destPath, path.relative(origPath, linkPath));
      return fsUnlink(filename).then(function() {
        return fsSymlink(nextTargetPath, filename);
      });
    });
  });
}

function main() {
  function check() {
    function checkReleasePath() {
      return fsExists(releaseExportPath).then(function(exists) {
        if (!exists) {
          error('no builds found');
        }
      });
    }

    function checkStorePath() {
      if (!shouldRewritePrefix) {
        return;
      }
      var storePath = getStorePathForPrefix(releasePackagePath);
      return fsExists(storePath).then(function(exists) {
        if (exists) {
          info('Release already installed, exiting...');
          process.exit(0);
        }
      });
    }

    return checkReleasePath().then(checkStorePath);
  }

  function initStore() {
    var storePath = shouldRewritePrefix
      ? getStorePathForPrefix(releasePackagePath)
      : unpaddedStorePath;
    return fsMkdir(storePath).then(function() {
      return Promise.all([
        fsMkdir(path.join(storePath, STORE_BUILD_TREE)),
        fsMkdir(path.join(storePath, STORE_INSTALL_TREE)),
        fsMkdir(path.join(storePath, STORE_STAGE_TREE))
      ]);
    });
  }

  function doImport() {
    function importBuilds() {
      return fsWalk(releaseExportPath).then(function(builds) {
        return Promise.all(
          builds.map(function(file) {
            var storePath = null;
            if (shouldRewritePrefix) {
              storePath = getStorePathForPrefix(releasePackagePath);
            }
            return importBuild(file.absolute, storePath);
          })
        );
      });
    }

    function rewriteBinWrappers() {
      if (!shouldRewritePrefix) {
        return;
      }
      var storePath = getStorePathForPrefix(releasePackagePath);
      return fsReadFile(path.join(releaseBinPath, '_storePath')).then(function(
        prevStorePath
      ) {
        prevStorePath = prevStorePath.toString();
        return rewritePaths(releaseBinPath, prevStorePath, storePath);
      });
    }

    return importBuilds().then(function() {
      return rewriteBinWrappers();
    });
  }

  return check()
    .then(initStore)
    .then(doImport);
}

process.on('unhandledRejection', error);

Promise.resolve()
  .then(main)
  .then(
    function() {
      info('Done!');
      process.exit(0);
    },
    function(err) {
      error(err);
    }
  );
