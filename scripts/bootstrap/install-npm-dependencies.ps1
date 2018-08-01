# This is a helper script to install NPM dependencies
#
# It's a temporary placeholder - right now, we can't install them via the `package.json`,
# because we need `esy` for that - if we try and use `yarn` or `npm`, it will fail due to
# the `opam` dependencies, and we don't have any `esy install` command on Windows yet!

function exitIfFailed() {
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
}

npm install esy-bash@0.1.19
npm install esy-ocaml/FastReplaceString.git#9450b6

npm install babel-preset-env
npm install babel-preset-flow
npm install del
npm install flow-bin
npm install fs-extra
npm install jest-cli
npm install prettier
npm install klaw
npm install minimatch
npm install semver
npm install super-resolve
npm install tar
npm install tar-fs
npm install tmp
npm install outdent
npm install rimraf

exitIfFailed
