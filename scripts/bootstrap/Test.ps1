# Windows initial test script
# This is just a VERY basic test exercising `esy install` and `esy build` for a canonical project:
# `hello-reason`
#
# This should be removed once we have the windows build hooked up to our existing test suite

function exitIfFailed() {
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
}

Write-Host "Cloning test repo.."
git clone https://github.com/esy-ocaml/hello-reason C:/erp
exitIfFailed
Write-Host "Clone complete!"
cd C:/erp
ls

# Install esy's dependencies so that we can run the jest tests

cd C:/projects/esy

 npm run test-e2e

 exitIfFailed
