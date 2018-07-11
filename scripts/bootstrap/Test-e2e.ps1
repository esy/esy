# Windows e2e test script
#
# This is a shim to make running the e2e tests work on Windows

function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

function exitIfFailed() {
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
}

$endToEndTestFolder = Join-Path (Get-ScriptDirectory) '../../test-e2e'

cd $endToEndTestFolder

yarn install; exitIfFailed;

node_modules/.bin/jest.cmd; exitIfFailed;
