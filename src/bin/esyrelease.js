/**
 * # Using And Releasing CLI apps.
 *
 * ### Using Released Packages
 *
 *     npm install -g git://github.com/reasonml/reason-cli.git#beta-v-1.13.5-dev
 *     npm install -g git://github.com/reasonml/reason-cli.git#beta-v-1.13.5-pack
 *     npm install -g git://github.com/reasonml/reason-cli.git#beta-v-1.13.5-bin-darwin
 *
 * There are three separate package releases for each version, which are simply
 * published "snapshots" of the typical full clean build. Throughout the process
 * of a full from scratch install and build, if you were to take snapshots along
 * the way, you'd see an increasingly simpler state of the world until finally you
 * end up with the pure binary release which does not need to download
 * dependencies, and does not need to build anything at all.
 *
 * The release utility performs this download/build/install process and snapshots
 * the state of the world at three separate moments. The three snapshots are named
 * `dev`, `pack`, and `bin`.
 *
 * **Dev**: Dev releases perform everything on the client installer machine
 * (download, build).
 *
 * **Pack**: Pack releases perform download and "pack"ing on the "server", and
 * then only builds will be performed on the client. This snapshots a giant
 * tarball of all dependencies' source files into the release.
 *
 * **Bin**: Bin releases perform everything on "the server", and "the client"
 * installs a package consisting only of binary executables.
 *
 * In the main repo's package.json, a list of `releasedBinaries` is provided,
 * which will expose npm binary wrappers for each of the specified binary names.
 * When creating releases the `actualInstall/package.json` is used as a template
 * for the packages that are actually build/installed.
 *
 * ### TroubleShooting
 *
 * Each published binary includes the built-in ability to troubleshoot where each
 * binary is resolved to.  If something is going wrong with your `refmt` command,
 * you can see which released binary `refmt` *actually* invokes in the release. We
 * use the `----where` flag with four `-` characters because it's unlikely to
 * conflict with any meaningful parameters of binaries like `refmt`.
 *
 * ```
 * refmt ----where
 *
 * > /path/to/npm-packages/lib/reason-cli/actualInstall/builds/reason/bin/refmt
 *
 * ```
 *
 * ### Wrapping Features:
 *
 * - Mitigates relocatability and cross platform packaging issues via command
 *   wrappers.
 * - When any one binary in the collection of "releasedBinaries" is invoked, that
 *   process can reference the other binaries in the collection without having to
 *   pay for wrapping cost. Suppose `merlin` invokes `refmt` often. Starting
 *   `merlin` via the released package, will ensure that `merlin`'s running
 *   process sees the `refmt` binary without the wrapper script.
 *
 *
 * ### Making New Releases
 *
 * Inside of your package's `package.json` field, specify a field `releasedBinaries:
 * ["exeName", "anotherName"]`, then these release utilities will automatically
 * create releasable packages that expose those binaries via npm's standard `bin`
 * feature. You won't populate the `bin` field in your `package.json` - the
 * release utilities will do so for you in the releases.
 *
 * The build stages are as follows. A release is created (essentially) by stopping
 * in between stages and publishing the state of the world to git/npm.
 *
 *     Dev -> Pack -> Bin
 *
 * If you `npm install` on the Dev Release, you essentially carry out the
 * remainder of the stages (Pack, and Bin) on the installing client.  If you `npm
 * install` the result of the Pack Release, you carry out the remaining stages on
 * the client (Bin). If you install the Bin release, you've installed the complete
 * compilation result onto the client.
 *
 * There's some slight differences between that simple description and what
 * actually happens: we might do some trivial configuration to set the build
 * destination to be different for the bin release etc.
 *
 *                                     RELEASE PROCESS
 *
 *
 *
 *      ○ make release TYPE=dev        ○ make release TYPE=pack      ○─ make release TYPE=bin
 *      │                              │                             │
 *      ○ trivial configuration        ○ trivial configuration       ○ trivial configuration
 *      │                              │                             │
 *      ●─ Dev Release                 │                             │
 *      .                              │                             │
 *      .                              │                             │
 *      ○ npm install                  │                             │
 *      │                              │                             │
 *      ○ Download dependencies        ○ Download dependencies       ○ Download dependencies
 *      │                              │                             │
 *      ○ Pack all dependencies        ○ Pack all dependencies       ○ Pack all dependencies
 *      │ into single tar+Makefile     │ into single tar+Makefile    │ into single tar+Makefile
 *      │                              │                             │
 *      │                              ●─ Pack Release               │
 *      │                              .                             │
 *      │                              .                             │
 *      │                              ○ npm install                 │
 *      │                              │                             │
 *      ○─ Build Binaries              ○─ Build Binaries             ○─ Build Binaries
 *      │                              │                             │
 *      │                              │                             ●─ Bin Release
 *      │                              │                             .
 *      │                              │                             .
 *      │                              │                             ○ npm install
 *      │                              │                             │
 *      ○─ Npm puts binaries in path   ○─ Npm puts binaries in path  ○─ Npm puts binaries in path.
 *
 *
 *
 * For BinRelease, it doesn't make sense to use any build cache, so the `Makefile`
 * at the root of this project substitutes placeholders in the generated binary
 * wrappers indicating where the build cache should be.
 *
 * > Relocating: "But aren't binaries built with particular paths encoded? How do
 * we distribute binaries that were built on someone else's machine?"
 *
 * That's one of the main challenges with distributing binaries. But most
 * applications that assume hard coded paths also allow overriding that hard
 * coded-ness in a wrapper script.  (Merlin, ocamlfind, and many more). Thankfully
 * we can have binary releases wrap the intended binaries that not only makes
 * Windows compatibility easier, but that also fixes many of the problems of
 * relocatability.
 *
 * > NOTE: Many binary npm releases include binary wrappers that correctly resolve
 * > the binary depending on platform, but they use a node.js script wrapper. The
 * > problem with this is that it can *massively* slow down build times when your
 * > builds call out to your binary which must first boot an entire V8 runtime. For
 * > `reason-cli` binary releases, we create lighter weight shell scripts that load
 * > in a fraction of the time of a V8 environment.
 *
 * The binary wrapper is generally helpful whether or *not* you are using
 * prereleased binaries vs. compiling from source, and whether or not you are
 * targeting linux/osx vs. Windows.
 *
 * When using Windows:
 *   - The wrapper script allows your linux and osx builds to produce
 *     `executableName.exe` files while still allowing your windows builds to
 *     produce `executableName.exe` as well.  It's usually a good idea to name all
 *     your executables `.exe` regardless of platform, but npm gets in the way
 *     there because you can't have *three* binaries named `executableName.exe`
 *     all installed upon `npm install -g`. Wrapper scripts to the rescue.  We
 *     publish two script wrappers per exposed binary - one called
 *     `executableName` (a shell script that works on Mac/Linux) and one called
 *     `executableName.cmd` (Windows cmd script) and npm will ensure that both are
 *     installed globally installed into the PATH when doing `npm install -g`, but
 *     in windows command line, `executableName` will resolve to the `.cmd` file.
 *     The wrapper script will execute the *correct* binary for the platform.
 * When using binaries:
 *   - The wrapper script will typically make *relocated* binaries more reliable.
 * When building pack or dev releases:
 *   - Binaries do not exist at the time the packages are installed (they are
 *     built in postinstall), but npm requires that bin links exists *at the time*
 *     of installation. Having a wrapper script allows you to publish `npm`
 *     packages that build binaries, where those binaries do not yet exist, yet
 *     have all the bin links installed correctly at install time.
 *
 * The wrapper scripts are common practice in npm packaging of binaries, and each
 * kind of release/development benefits from those wrappers in some way.
 *
 * TODO:
 *  - Support local installations of <package_name> which would work for any of
 *    the three release forms.
 *    - With the wrapper script, it might already even work.
 *  - Actually create `.cmd` launcher.
 *
 * NOTES:
 *
 *  We maintain two global variables that wrappers consult:
 *
 *  - `<PACKAGE_NAME>_ENVIRONMENT_SOURCED`: So that if one wrapped binary calls
 *    out to another we don't need to repeatedly setup the path.
 *
 *  - `<PACKAGE_NAME>_ENVIRONMENT_SOURCED_<binary_name>`: So that if
 *    `<binary_name>` ever calls out to the same `<binary_name>` script we know
 *    it's because the environment wasn't sourced correctly and therefore it is
 *    infinitely looping.  An early check detects this.
 *
 *  Only if we even need to compute the environment will we do the expensive work
 *  of sourcing the paths. That makes it so merlin can repeatedly call
 *  `<binary_name>` with very low overhead for example.
 *
 *  If the env didn't correctly load and no `<binary_name>` shadows it, this will
 *  infinitely loop. Therefore, we put a check to make sure that no
 *  `<binary_name>` calls out to ocaml again. See
 *  `<PACKAGE_NAME>_ENVIRONMENT_SOURCED_<binary_name>`
 *
 */

var fs = require('fs');
var path = require('path');
var child_process = require('child_process');

var storeVersion = '3.x.x';

var tagName =
  process.env['VERSION'] +
  '-' +
  process.env['TYPE'] +
  (process.env['TYPE'] === 'bin' ? '-' + require('os').platform() : '');

/**
 * TODO: Make this language agnostic. Nothing else in the eject/build process
 * is really specific to Reason/OCaml.  Binary _install directories *shouldn't*
 * contain some of these artifacts, but very often they do. For other
 * extensions, they are left around for the sake of linking/building against
 * those packages, but aren't useful as a form of binary executable releases.
 * This cleans up those files that just bloat the installation, creating a lean
 * executable distribution.
 */
var extensionsToDeleteForBinaryRelease = [
  "Makefile",
  "README",
  "CHANGES",
  "LICENSE",
  "_tags",
  "*.pdf",
  "*.md",
  "*.org",
  "*.org",
  "*.txt"
];

var pathPatternsToDeleteForBinaryRelease = [
  '*/doc/*'
];

var scrubBinaryReleaseCommandExtensions = function(searchDir) {
  return 'find ' + searchDir + ' -type f \\( -name ' +
  extensionsToDeleteForBinaryRelease.map((ext) => {return "'" + ext + "'";})
    .join(' -o -name ') +
    ' \\) -delete';
};

var scrubBinaryReleaseCommandPathPatterns = function(searchDir) {
  return 'find ' + searchDir + ' -type f \\( -path ' +
  pathPatternsToDeleteForBinaryRelease
    .join(' -o -path ') +
    ' \\) -delete';
};

var startMsg =`
--------------------------------------------
-- Preparing release ${tagName} --
--------------------------------------------
`;
var almostDoneMsg = `
----------------------------------------------------
-- Almost Done. Complete the following two steps ---
----------------------------------------------------

Directory package/ contains a git repository ready
to be pushed under a tag to remote.

1. [REQUIRED] cd package

2. git show HEAD
   Make sure you approve of what will be pushed to tag ${tagName}

3. git push origin HEAD:branch-${tagName}
   Push a release branch if needed.

4. [REQUIRED] git push origin ${tagName}
   Push a release tag.

You can test install the release by running:

    npm install '${process.env['ORIGIN']}'#${tagName}

> Note: If you are pushing an update to an existing tag, you might need to add -f to the push command.
`

var postinstallScriptSupport = `
    # Exporting so we can call it from xargs
    # https://stackoverflow.com/questions/11003418/calling-functions-with-xargs-within-a-bash-script
    unzipAndUntarFixupLinks() {
      serverEsyEjectStore=$1
      gunzip "$2"
      # Beware of the issues of using "which". https://stackoverflow.com/a/677212
      # Also: hash is only safe/reliable to use in bash, so make sure shebang line is bash.
      if hash bsdtar 2>/dev/null; then
        bsdtar -s "|\${serverEsyEjectStore}|\${ESY_EJECT__INSTALL_STORE}|gs" -xf ./\`basename "$2" .gz\`
      else
        if hash tar 2>/dev/null; then
          # Supply --warning=no-unknown-keyword to supresses warnings when packed on OSX
          tar --warning=no-unknown-keyword --transform="s|\${serverEsyEjectStore}|\${ESY_EJECT__INSTALL_STORE}|" -xf ./\`basename "$2" .gz\`
        else
          echo >&2 "Installation requires either bsdtar or tar - neither is found.  Aborting.";
        fi
      fi
      # remove the .tar file
      rm ./\`basename "$2" .gz\`
    }
    export -f unzipAndUntarFixupLinks

    printByteLengthError() {
      echo >&2 "ERROR:";
      echo >&2 "  $1";
      echo >&2 "Could not perform binary build or installation because the location you are installing to ";
      echo >&2 "is too 'deep' in the file system. That sounds like a strange limitation, but ";
      echo >&2 "the scripts contain shebangs that encode this path to executable, and posix ";
      echo >&2 "systems limit the length of those shebang lines to 127.";
      echo >&2 "";
    }
    repeatCh() {
     chToRepeat=$1
     times=$2
     printf "%0.s$chToRepeat" $(seq 1 $times)
    }
    STRLEN_RESULT=0
    strLen() {
      oLang=$LANG
      LANG=C
      STRLEN_RESULT=\${#1}
      LANG=$oLang
    }
    checkEsyEjectStore() {
      if [[ $ESY_EJECT__STORE == *"//"* ]]; then
        echo >&2 "ESY_EJECT__STORE($ESY_EJECT__STORE) has an invalid pattern \/\/";
        exit 1;
      fi
      if [[ $ESY_EJECT__STORE != "/"* ]]; then
        echo >&2 "ESY_EJECT__STORE($ESY_EJECT__STORE) does not begin with a forward slash - it must be absolute.";
        exit 1;
      fi
      if [[ $ESY_EJECT__STORE == *"/./"*  ]]; then
        echo >&2 "ESY_EJECT__STORE($ESY_EJECT__STORE) contains \/\.\/ and that is not okay.";
        exit 1;
      fi
      if [[ $ESY_EJECT__STORE == *"/"  ]]; then
        echo >&2 "ESY_EJECT__STORE($ESY_EJECT__STORE) ends with a slash and it should not";
        exit 1;
      fi
    }
`;

var launchBinScriptSupport = `
    STRLEN_RESULT=0
    strLen() {
      oLang=$LANG
      LANG=C
      STRLEN_RESULT=\${#1}
      LANG=$oLang
    }
    printError() {
      echo >&2 "ERROR:";
      echo >&2 "$0 command is not installed correctly. ";
      TROUBLESHOOTING="When installing <package_name>, did you see any errors in the log? "
      TROUBLESHOOTING="$TROUBLESHOOTING - What does (which <binary_name>) return? "
      TROUBLESHOOTING="$TROUBLESHOOTING - Please file a github issue on <package_name>'s repo."
      echo >&2 "$TROUBLESHOOTING";
    }
`;

var escapeBashVarName = function(str) {
  var map = {'.': 'd', '_': '_', '-': 'h'};
  var replacer = match => map.hasOwnProperty(match) ? "_"+map[match] : match;
  return str.replace(/./g, replacer);
}

var getReleasedBinaries = function(package) {
  return package && package.esy && package.esy.release && package.esy.release.releasedBinaries;
}

var createLaunchBinSh = function(releaseType, package, binaryName) {
  var packageName = package.name;
  var packageNameUppercase = escapeBashVarName(package.name.toUpperCase());
  var binaryNameUppercase = escapeBashVarName(binaryName.toUpperCase());
  var releasedBinaries = getReleasedBinaries(package);
  return `#!/usr/bin/env bash

export ESY__STORE_VERSION=${storeVersion}
${launchBinScriptSupport}
if [ -z \${${packageNameUppercase}__ENVIRONMENTSOURCED__${binaryNameUppercase}+x} ]; then
  if [ -z \${${packageNameUppercase}__ENVIRONMENTSOURCED+x} ]; then
    # In windows this woudl be: a simple: %~dp0
    SOURCE="\${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
      SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$SCRIPTDIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    export ESY_EJECT__SANDBOX="$SCRIPTDIR/../rel"
    export PACKAGE_ROOT="$SCRIPTDIR/.."
    # Remove dependency on esy and package managers in general
    # We fake it so that the eject store is the location where we relocated the
    # binaries to.
    export ESY_EJECT__STORE=\`cat $PACKAGE_ROOT/records/recordedClientInstallStorePath.txt\`
    ENV_PATH="$ESY_EJECT__SANDBOX/node_modules/.cache/_esy/build-eject/eject-env"
    source "$ENV_PATH"
    export ${packageNameUppercase}__ENVIRONMENTSOURCED="sourced"
    export ${packageNameUppercase}__ENVIRONMENTSOURCED__${binaryNameUppercase}="sourced"
  fi
  command -v $0 >/dev/null 2>&1 || {
    printError;
    exit 1;
  }
${
  binaryName !== packageName ?
  `
  if [ "$1" == "----where" ]; then
     which "${binaryName}"
  else
    exec "${binaryName}" "$@"
  fi
  ` :
  `
  if [[ "$1" == ""  ]]; then
    echo ""
    echo "Welcome to ${packageName}"
    echo "-------------------------"
    echo "Installed Binaries: [" ${(releasedBinaries || []).concat([packageName]).join(',')} "]"
    echo "- ${packageName} bash"
    echo   " Starts bash from the perspective of ${(releasedBinaries || ['<no_binaries>'])[0]} and installed binaries."
    echo "- binaryName ----where"
    echo "  Prints the location of binaryName"
    echo "  Example: ${(package.releasedBinaries || ['<no_binaries>'])[0]} ----where"
    echo "- Note: Running builds and scripts from within "${packageName} bash" will typically increase performance of builds."
    echo ""
  else
    if [ "$1" == "bash" ]; then
      # Important to pass --noprofile, and --rcfile so that the user's
      # .bashrc doesn't run and the npm global packages don't get put in front
      # of the already constructed PATH.
      bash --noprofile --rcfile <(echo 'export PS1="${'\033[0;31m⏣ ' + packageName + ': \033[0m$PS1'}"')
    else
      echo "Invalid argument $1, type reason-cli for help"
    fi
  fi
  `
}
else
  printError;
  exit 1;
fi
`
};

var debug = process.env['DEBUG'];

var packageDir = path.resolve(__dirname, '..');

process.chdir(packageDir);

var logExec = function (cmd) {
  if (debug) {
    console.log('LOG:', cmd);
  }
  child_process.execSync(cmd, {stdio: 'inherit'});
}

var types = ['dev', 'pack', 'bin'];
var releaseStage = ['forPreparingRelease', 'forClientInstallation'];

var actions = {
  'dev': {
    installEsy: 'forClientInstallation',
    download: 'forClientInstallation',
    pack: 'forClientInstallation',
    compressPack: '',
    decompressPack: '',
    buildPackages: 'forClientInstallation',
    compressBuiltPackages: 'forClientInstallation',
    decompressAndRelocateBuiltPackages: 'forClientInstallation'
  },
  'pack': {
    installEsy: 'forPreparingRelease',
    download: 'forPreparingRelease',
    pack: 'forPreparingRelease',
    compressPack: 'forPreparingRelease',
    decompressPack: 'forClientInstallation',
    buildPackages: 'forClientInstallation',
    compressBuiltPackages: 'forClientInstallation',
    decompressAndRelocateBuiltPackages: 'forClientInstallation'
  },
  'bin': {
    installEsy: 'forPreparingRelease',
    download: 'forPreparingRelease',
    pack: 'forPreparingRelease',
    compressPack: '',
    decompressPack: '',
    buildPackages: 'forPreparingRelease',
    compressBuiltPackages: 'forPreparingRelease',
    decompressAndRelocateBuiltPackages: 'forClientInstallation'
  }
};

var buildLocallyAndRelocate = {
  'dev': false,
  'pack': false,
  'bin': true
};

/**
 * Derive npm release package.
 *
 * This strips all dependency info and add "bin" metadata.
 */
var deriveNpmReleasePackage = function(package, packageDir, releaseType) {
  var copy = JSON.parse(JSON.stringify(package));

  // We don't manage dependencies with npm, esy is being installed via a
  // postinstall script and then it is used to manage release dependencies.
  copy.dependencies = {};
  copy.devDependencies = {};

  // Populate "bin" metadata.
  logExec('mkdir -p .bin');
  var binsToWrite = getBinsToWrite(releaseType, packageDir, package);
  var packageJsonBins = {};
  for (var i = 0; i < binsToWrite.length; i++) {
    var toWrite = binsToWrite[i];
    fs.writeFileSync(toWrite.path, toWrite.contents);
    fs.chmodSync(toWrite.path, 0755);
    packageJsonBins[toWrite.name] = toWrite.path;
  }
  var copy = addBins(packageJsonBins, copy);

  // Add postinstall script
  copy.scripts.postinstall = './postinstall.sh';

  return copy
}

/**
 * Derive esy release package.
 */
var deriveEsyReleasePackage = function(package, packageDir, releaseType) {
  var copy = JSON.parse(JSON.stringify(package));
  delete copy.dependencies.esy;
  delete copy.devDependencies.esy;
  return copy;
}

/**
 * We get to remove a ton of dependencies for pack and bin based releases since
 * we don't need to even perform package management for native modules -
 * everything is vendored.
 */
var adjustReleaseDependencies =  function(releaseStage, releaseType, package) {
  var copy = JSON.parse(JSON.stringify(package));
  // We don't need dependency on Esy as we install it manually.
  if (copy.dependencies && copy.dependencies.esy) {
    delete copy.dependencies.esy;
  }
  if (copy.devDependencies && copy.devDependencies.esy) {
    delete copy.devDependencies.esy;
  }

  if (actions[releaseType].download !== releaseStage) {
    copy.dependencies = {};
    copy.devDependencies = {};
  }

  return copy;
};

var addBins = function(bins, package) {
  var copy = JSON.parse(JSON.stringify(package));
  copy.bin = bins;
  delete copy.releasedBinaries;
  return copy;
};

var addPostinstallScript = function(package) {
  var copy = JSON.parse(JSON.stringify(package));
  copy.scripts = copy.scripts || {};
  copy.scripts.postinstall = './postinstall.sh';
  return copy;
};

var removePostinstallScript = function(package) {
  var copy = JSON.parse(JSON.stringify(package));
  copy.scripts = copy.scripts || {};
  copy.scripts.postinstall = '';
  return copy;
};

var putJson = function(filename, package) {
  fs.writeFileSync(filename, JSON.stringify(package, null, 2));
};

var verifyBinSetup = function(package) {
  var whosInCharge = ' Run make clean first. The release script needs to be in charge of generating the binaries.';
  var binDirExists = fs.existsSync('./.bin');
  if (binDirExists) {
    throw new Error(whosInCharge + 'Found existing binaries dir .bin. This should not exist. Release script creates it.');
  }
  if (package.bin) {
    throw new Error(whosInCharge + 'Package.json has a bin field. It should have a "releasedBinaries" field instead - a list of released binary names.');
  }
};


/**
 * To relocate binary artifacts: We need to make sure that the length of
 * shebang lines do not exceed 127 (common on most linuxes).
 *
 * For binary releases, they will be built in the form of:
 *
 *        This will be replaced by the actual      This must remain.
 *        install location.
 *       +------------------------------+  +--------------------------------+
 *      /                                \/                                  \
 *   #!/path/to/rel/store___padding____/i/ocaml-4.02.3-d8a857f3/bin/ocamlrun
 *
 * The goal is to make this path exactly 127 characters long (maybe a little
 * less to allow room for some other shebangs like `ocamlrun.opt` etc?)
 *
 * Therefore, it is optimal to make this path as long as possible, but no
 * longer than 127 characters, while minimizing the size of the final
 * "ocaml-4.02.3-d8a857f3/bin/ocamlrun" portion. That allows installation of
 * the release in as many destinations as possible.
 */
var desiredShebangPathLength = 127 - "!#".length;
var pathLengthConsumedByOcamlrun = "/i/ocaml-n.00.0-########/bin/ocamlrun".length;
var desiredEsyEjectStoreLength = desiredShebangPathLength - pathLengthConsumedByOcamlrun;
var createInstallScript = function(releaseStage, releaseType, package) {
  var shouldInstallEsy = actions[releaseType].installEsy === releaseStage;
  var shouldDownload = actions[releaseType].download === releaseStage;
  var shouldPack = actions[releaseType].pack === releaseStage;
  var shouldCompressPack = actions[releaseType].compressPack === releaseStage;
  var shouldDecompressPack = actions[releaseType].decompressPack === releaseStage;
  var shouldBuildPackages = actions[releaseType].buildPackages === releaseStage;
  var shouldCompressBuiltPackages = actions[releaseType].compressBuiltPackages === releaseStage;
  var shouldDecompressAndRelocateBuiltPackages = actions[releaseType].decompressAndRelocateBuiltPackages === releaseStage;
  var message =`
    # Release releaseType: "${releaseType}"
    # ------------------------------------------------------
    #  Executed ${releaseStage === 'forPreparingRelease' ? 'while creating the release' : 'while installing the release on client machine'}
    #
    #  Install Esy: ${shouldInstallEsy}
    #  Download: ${shouldDownload}
    #  Pack: ${shouldPack}
    #  Compress Pack: ${shouldCompressPack}
    #  Decompress Pack: ${shouldDecompressPack}
    #  Build Packages: ${shouldBuildPackages}
    #  Compress Built Packages: ${shouldCompressBuiltPackages}
    #  Decompress Built Packages: ${shouldDecompressAndRelocateBuiltPackages}`;

  var deleteFromBinaryRelease = package.esy && package.esy.release && package.esy.release.deleteFromBinaryRelease;
  var esyCommand = '../_esy/bin/esy';

  var installEsyCmds = `
    # Install Esy
    echo '*** Installing Esy...'
    npm install --global --prefix ./_esy "esy@${package.esy.esyDependency}"
  `;

  var downloadCmds = `
    # Download
    echo '*** Installing dependencies...'
    cd ./rel
    ${esyCommand} install
    cd ../
  `;
  var packCmds = `
    # Pack:
    # Peform build eject.  Warms up *just* the artifacts that require having a
    # modern node installed.
    # Generates the single Makefile etc.
    cd ./rel
    ${esyCommand} build-eject
    cd ../
  `;
  var compressPackCmds = `
    # Compress:
    # Avoid npm stripping out vendored node_modules via tar. Merely renaming node_modules
    # is not sufficient!
    echo '*** Packing the release...'
    tar -czf rel.tar.gz rel
    rm -rf ./rel/`;
  var decompressPackCmds =`
    # Decompress:
    # Avoid npm stripping out vendored node_modules.
    echo '*** Unpacking the release...'
    gunzip rel.tar.gz
    if hash bsdtar 2>/dev/null; then
      bsdtar -xf rel.tar
    else
      if hash tar 2>/dev/null; then
        # Supply --warning=no-unknown-keyword to supresses warnings when packed on OSX
        tar --warning=no-unknown-keyword -xf rel.tar
      else
        echo >&2 "Installation requires either bsdtar or tar - neither is found.  Aborting.";
      fi
    fi
    rm -rf rel.tar`;
  var buildPackagesCmds = `
    # BuildPackages: Always reserve enough path space to perform relocation.
    echo '*** Building the release...'
    cd ./rel/
    make -j -f node_modules/.cache/_esy/build-eject/Makefile
    cd ..
    mkdir $PACKAGE_ROOT/records
    echo "$ESY_EJECT__STORE" > "$PACKAGE_ROOT/records/recordedServerBuildStorePath.txt"
    # For client side builds, recordedServerBuildStorePath is equal to recordedClientBuildStorePath.
    # For prebuilt binaries these will differ, and recordedClientBuildStorePath.txt is overwritten.
    echo "$ESY_EJECT__STORE" > "$PACKAGE_ROOT/records/recordedClientBuildStorePath.txt"`;

  /**
   * In bash:
   * [[ "hellow4orld" =~ ^h(.[a-z]*) ]] && echo ${BASH_REMATCH[0]}
   * Prints out: hellow
   * [[ "zzz" =~ ^h(.[a-z]*) ]] && echo ${BASH_REMATCH[1]}
   * Prints out: ellow
   * [[ "zzz" =~ ^h(.[a-z]*) ]] && echo ${BASH_REMATCH[1]}
   * Prints out empty
   */
  var compressBuiltPackagesCmds = `
    ENV_PATH="$ESY_EJECT__SANDBOX/node_modules/.cache/_esy/build-eject/eject-env"
    # Double backslash in es6 literals becomes one backslash
    # Must use . instead of source for some reason.
    shCmd=". $ENV_PATH && echo \\$PATH"
    EJECTED_PATH=\`sh -c "$shCmd"\`
    # Remove the sources, keep the .cache which has some helpful information.
    mv "$ESY_EJECT__SANDBOX/node_modules" "$ESY_EJECT__SANDBOX/node_modules_tmp"
    mkdir -p "$ESY_EJECT__SANDBOX/node_modules"
    mv "$ESY_EJECT__SANDBOX/node_modules_tmp/.cache" "$ESY_EJECT__SANDBOX/node_modules/.cache"
    rm -rf "$ESY_EJECT__SANDBOX/node_modules_tmp"
    # Copy over the installation artifacts.

    mkdir -p "$ESY_EJECT__TMP/i"
    # Grab all the install directories by scraping what was added to the PATH.
    # This deserves a better supported approach directly from esy.
    IFS=':' read -a arr <<< "$EJECTED_PATH"
    for i in "\${arr[@]}"; do
      res=\`[[   "$i" =~ ^("$ESY_EJECT__STORE"/i/[a-z0-9\._-]*) ]] && echo \${BASH_REMATCH[1]} || echo ''\`
      if [[ "$res" != ""  ]]; then
        cp -r "$res" "$ESY_EJECT__TMP/i/"
        cd "$ESY_EJECT__TMP/i/"
        tar -czf \`basename "$res"\`.tar.gz \`basename "$res"\`
        rm -rf \`basename "$res"\`
        echo "$res" >> $PACKAGE_ROOT/records/recordedCoppiedArtifacts.txt
      fi
    done
    unset IFS
    cd "$PACKAGE_ROOT"
    ${releaseStage === 'forPreparingRelease' ? scrubBinaryReleaseCommandPathPatterns('"$ESY_EJECT__TMP/i/"') : '#'}
    ${releaseStage === 'forPreparingRelease' ?
      (deleteFromBinaryRelease || []).map(function(pattern) {
        return 'rm ' + pattern;
      }).join('\n') : ''
    }
    # Built packages have a special way of compressing the release, putting the
    # eject store in its own tar so that all the symlinks in the store can be
    # relocated using tools that exist in the eject sandbox.

    tar -czf rel.tar.gz rel
    rm -rf ./rel/`;
  var decompressAndRelocateBuiltPackagesCmds = `

    if [ -d "$ESY_EJECT__INSTALL_STORE" ]; then
      echo >&2 "$ESY_EJECT__INSTALL_STORE already exists. This will not work. It has to be a new directory.";
      exit 1;
    fi
    serverEsyEjectStore=\`cat "$PACKAGE_ROOT/records/recordedServerBuildStorePath.txt"\`
    serverEsyEjectStoreDirName=\`basename "$serverEsyEjectStore"\`

    # Decompress the actual sandbox:
    unzipAndUntarFixupLinks "$serverEsyEjectStore" "rel.tar.gz"

    cd "$ESY_EJECT__TMP/i/"
    # Executing the untar/unzip in parallel!
    echo '*** Decompressing artefacts...'
    find . -name '*.gz' -print0 | xargs -0 -I {} -P 30 bash -c "unzipAndUntarFixupLinks $serverEsyEjectStore {}"

    cd "$PACKAGE_ROOT"
    mv "$ESY_EJECT__TMP" "$ESY_EJECT__INSTALL_STORE"
    # Write the final store path, overwritting the (original) path on server.
    echo "$ESY_EJECT__INSTALL_STORE" > "$PACKAGE_ROOT/records/recordedClientInstallStorePath.txt"

    # Not that this is really even used for anything once on the client.
    # We use the install store. Still, this might be good for debugging.
    echo "$ESY_EJECT__STORE" > "$PACKAGE_ROOT/records/recordedClientBuildStorePath.txt"
    # Executing the replace string in parallel!
    # https://askubuntu.com/questions/431478/decompressing-multiple-files-at-once
    echo '*** Relocating artefacts to the final destination...'
    find $ESY_EJECT__INSTALL_STORE -type f -print0 | xargs -0 -I {} -P 30 "$ESY_EJECT__SANDBOX/node_modules/.cache/_esy/build-eject/bin/fastreplacestring.exe" "{}" "$serverEsyEjectStore" "$ESY_EJECT__INSTALL_STORE"
    `;
  // Notice how we comment out each section which doesn't apply to this
  // combination of releaseStage/releaseType.
  var installEsy = installEsyCmds.split('\n').join(shouldInstallEsy ? '\n' : '\n#');
  var download = downloadCmds.split('\n').join(shouldDownload ? '\n' : '\n#');
  var pack = packCmds.split('\n').join(shouldPack ? '\n' : '\n#');
  var compressPack = compressPackCmds.split('\n').join(shouldCompressPack ? '\n' : '\n#');
  var decompressPack = decompressPackCmds.split('\n').join(shouldDecompressPack ? '\n' : '\n#');
  var buildPackages = buildPackagesCmds.split('\n').join(shouldBuildPackages ? '\n' : '\n#');
  var compressBuiltPackages = compressBuiltPackagesCmds.split('\n').join(shouldCompressBuiltPackages ? '\n' : '\n#');
  var decompressAndRelocateBuiltPackages =
      decompressAndRelocateBuiltPackagesCmds.split('\n').join(shouldDecompressAndRelocateBuiltPackages ? '\n' : '\n#');
  return `#!/usr/bin/env bash
    set -e
    ${postinstallScriptSupport}
    ${message}

    #                server               |              client
    #                                     |
    # ESY_EJECT__STORE -> ESY_EJECT__TMP  |  ESY_EJECT__TMP -> ESY_EJECT__INSTALL_STORE
    # =================================================================================

    ESY__STORE_VERSION="${storeVersion}"
    SOURCE="\${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
      SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$SCRIPTDIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    export ESY_EJECT__SANDBOX="$SCRIPTDIR/rel"

    # We allow the ESY_EJECT__STORE to be customized at build time. But at
    # install time, we always want to copy the artifacts to the install
    # directory. We need to distinguish between where artifacts are build
    # into, and where they are relocated to.
    # Regardless of if we're building on the client or server, when building
    # we usually want to default the store to the global cache. Then we can
    # copy the artifacts into the release, and use that as the eject store
    # when running binaries etc. This will ensure that no matter what - binary
    # or pack modes, you get artifacts coppied and relocated into your
    # installation so there are no dangling things.
    if [ -z "\${PRENORMALIZED_ESY_EJECT__STORE+x}" ]; then
      PRENORMALIZED_ESY_EJECT__STORE="$HOME/.esy/$ESY__STORE_VERSION"
    else
      PRENORMALIZED_ESY_EJECT__STORE="$PRENORMALIZED_ESY_EJECT__STORE"
    fi
    # Remove trailing slash if any.
    PRENORMALIZED_ESY_EJECT__STORE="\${PRENORMALIZED_ESY_EJECT__STORE%/}"
    strLen "$PRENORMALIZED_ESY_EJECT__STORE"
    lenPrenormalizedEsyEjectStore=$STRLEN_RESULT
    byteLenDiff=\`expr ${desiredEsyEjectStoreLength} - $lenPrenormalizedEsyEjectStore \`
    # Discover how much of the reserved relocation padding must be consumed.
    if [ "$byteLenDiff" -lt "0" ]; then
      printByteLengthError "$PRENORMALIZED_ESY_EJECT__STORE";
       exit 1;
    fi
    adjustedSuffix=\`repeatCh '_' "$byteLenDiff"\`
    export ESY_EJECT__STORE="\${PRENORMALIZED_ESY_EJECT__STORE}$adjustedSuffix"


    # We Build into the ESY_EJECT__STORE, copy into ESY_EJECT__TMP, potentially
    # transport over the network then finally we copy artifacts into the
    # ESY_EJECT__INSTALL_STORE and relocate them as if they were built there to
    # begin with.  ESY_EJECT__INSTALL_STORE should not ever be used if we're
    # running on the server.
    PRENORMALIZED_ESY_EJECT__INSTALL_STORE="$ESY_EJECT__SANDBOX/$ESY__STORE_VERSION"
    # Remove trailing slash if any.
    PRENORMALIZED_ESY_EJECT__INSTALL_STORE="\${PRENORMALIZED_ESY_EJECT__INSTALL_STORE%/}"
    strLen "$PRENORMALIZED_ESY_EJECT__INSTALL_STORE"
    lenPrenormalizedEsyEjectInstallStore=$STRLEN_RESULT
    byteLenDiff=\`expr ${desiredEsyEjectStoreLength} - $lenPrenormalizedEsyEjectInstallStore \`
    # Discover how much of the reserved relocation padding must be consumed.
    if [ "$byteLenDiff" -lt "0" ]; then
      printByteLengthError "$PRENORMALIZED_ESY_EJECT__INSTALL_STORE";
       exit 1;
    fi
    adjustedSuffix=\`repeatCh '_' "$byteLenDiff"\`
    export ESY_EJECT__INSTALL_STORE="\${PRENORMALIZED_ESY_EJECT__INSTALL_STORE}$adjustedSuffix"


    # Regardless of where artifacts are actually built, or where they will be
    # installed to, or if we're on the server/client we will copy artifacts
    # here temporarily. Sometimes the build location is the same as where we
    # copy them to inside the sandbox - sometimes not.
    export PACKAGE_ROOT="$SCRIPTDIR"
    export ESY_EJECT__TMP="$PACKAGE_ROOT/relBinaries"

    checkEsyEjectStore
    ${installEsy}
    ${download}
    ${pack}
    ${compressPack}
    ${decompressPack}
    ${buildPackages}
    ${compressBuiltPackages}
    ${decompressAndRelocateBuiltPackages}`
};

var getBinsToWrite = function(releaseType, packageDir, package) {
  var ret = [];
  var releasedBinaries = getReleasedBinaries(package);
  if (releasedBinaries) {
    for (var i = 0; i < releasedBinaries.length; i++) {
      var binaryName = releasedBinaries[i];
      var destPath = path.join('.bin', binaryName);
      ret.push({
        name: binaryName,
        path: destPath,
        contents: createLaunchBinSh(releaseType, package, binaryName)
      });
      /*
       * ret.push({
       *   name: binaryName + '.cmd',
       *   path: path.join(destPath + '.cmd'),
       *   contents: createLaunchBinSh(releaseType, packageNameUppercase, binaryName)
       * });
       */
    }
  }
  var destPath = path.join('.bin', package.name);
  ret.push({
    name: package.name,
    path: destPath,
    contents: createLaunchBinSh(releaseType, package, package.name)
  });
  return ret;
};

var checkVersion = function() {
  if (!process.env['VERSION']) {
    throw new Error('VERSION is undefined. Usage: make release VERSION=beta-v-0.0.1 TYPE=dev|pack|bin');
  }
};

var checkOrigin = function() {
  if (!process.env['ORIGIN']) {
    throw new Error('ORIGIN is undefined. The Makefile wrapper should have set this.');
  }
};

var checkReleaseType = function() {
  if (process.env['TYPE'] !== 'dev' && process.env['TYPE'] !== 'pack' &&  process.env['TYPE'] !== 'bin') {
    throw new Error('TYPE is undefined or invalid. Usage: make release VERSION=beta-v-0.0.1 TYPE=dev|pack|bin');
  }
};

var checkNoChanges = function(packageDir) {
  logExec(
    'git diff --exit-code || (echo ""  && echo "!!You have unstaged changes. Please clean up first." && exit 1)'
  );
  logExec(
    'git diff --cached --exit-code || (echo "" && echo "!!You have staged changes. Please reset them or commit them first." && exit 1)'
  );
};

var putExecutable = function(filename, contents) {
  fs.writeFileSync(filename, contents);
  fs.chmodSync(filename, 0755);
}

var readPackageJson = function(filename) {
  var packageJson = fs.readFileSync(filename, 'utf8');
  var package = JSON.parse(packageJson);
  // Perform normalizations
  if (package.dependencies == null) {
    package.dependencies = {};
  }
  if (package.devDependencies == null) {
    package.devDependencies = {};
  }
  if (package.scripts == null) {
    package.scripts = {};
  }
  if (package.esy == null) {
    package.esy = {};
  }
  if (package.esy.release == null) {
    package.esy.release = {};
  }
  // Store esy dependency info separately so we can handle it in postinstall
  // scirpt independently of npm dependency management.
  var esyDependency = package.dependencies.esy || package.devDependencies.esy;
  if (esyDependency == null) {
    throw new Error('package should have esy declared as dependency');
  }
  package.esy.esyDependency = esyDependency;
  return package;
}

/**
 * Builds the release from within the rootDirectory/package/ directory created
 * by `npm pack` command.
 */
exports.buildRelease = function() {
  var releaseType = process.env['TYPE'];
  var packageDir = path.resolve(__dirname, '..');

  checkVersion();
  checkReleaseType();
  //checkNoChanges();

  var package = readPackageJson('./package.json');
  verifyBinSetup(package);

  console.log(`*** Creating ${releaseType}-type release for ${package.name}`);

  var npmPackage = deriveNpmReleasePackage(package, packageDir, releaseType);
  putJson(path.join(packageDir, 'package.json'), npmPackage);

  var esyPackage = deriveEsyReleasePackage(package, packageDir, releaseType);
  fs.mkdirSync(path.join(packageDir, 'rel'));
  putJson(path.join(packageDir, 'rel', 'package.json'), esyPackage);

  putExecutable(
    path.join(packageDir, 'prerelease.sh'),
    createInstallScript('forPreparingRelease', releaseType, package)
  );

  logExec('./prerelease.sh');

  logExec('rm -rf ' + path.join(packageDir, 'node_modules'));
  logExec('rm -rf ' + path.join(packageDir, 'rel', 'yarn.lock'));

  // Actual Release: We leave the *actual* postinstall script to be executed on the host.
  putExecutable(
    path.join(packageDir, 'postinstall.sh'),
    createInstallScript('forClientInstallation', releaseType, package)
  );
};


exports.release = function(forGithubLFS) {
  console.log(startMsg);
  [
    'git init',
    'git checkout -b branch-' + tagName + '',
    forGithubLFS ? 'git lfs track ./rel.tar.gz' : '',
    forGithubLFS ? 'git lfs track relBinaries/i/*.tar.gz' : '',
    'git add .',
    'git remote add origin ' + process.env['ORIGIN'],
    'git fetch --tags --depth=1',
    'git commit -m "Preparing release ' + tagName + '"',
    '# Return code is inverted to receive boolean return value',
    '(git tag --delete ' + tagName + ' &> /dev/null) || echo "Tag ' + tagName + ' doesn\'t yet exist, creating it now."',
    'git tag -a ' + tagName + ' -m "' + tagName + '"',
  ].forEach(function(cmd) {
    if (cmd) {
      logExec(cmd);
    }
  });
  console.log (almostDoneMsg);
};


