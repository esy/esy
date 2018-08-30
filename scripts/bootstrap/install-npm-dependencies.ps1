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

# If updating the version for this,
# make sure to also update it in `scripts/release-postinstall.js`, too!
npm install esy-bash@0.1.22

exitIfFailed
