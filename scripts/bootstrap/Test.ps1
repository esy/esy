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

mkdir C:/esy-home
$env:HOME="C:/esy-home"


# Install esy's dependencies so that we can run the jest tests

cd C:/projects/esy

C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe legacy-install
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe legacy-install
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe legacy-install

 exitIfFailed

 npm run test-e2e
