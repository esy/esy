# Windows e2e test script
#
# This is a shim to make running the e2e tests work on Windows

function exitIfFailed() {
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
}

cd /esy3/test-e2e

yarn install; exitIfFailed;

node_modules/.bin/jest.cmd; exitIfFailed;
