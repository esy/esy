# Windows initial test script
# This is just a VERY basic test exercising `esy install` and `esy build` for a canonical project:
# `esy-reason-project`
#
# This should be removed once we have the windows build hooked up to our existing test suite

function exitIfFailed() {
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
}

Write-Host "Cloning test repo.."
git clone https://github.com/esy-ocaml/esy-reason-project C:/erp
exitIfFailed
Write-Host "Clone complete!"
cd C:/erp
ls

mkdir C:/esy-home
$env:HOME="C:/esy-home"

# "Integration Test" for now
# This requires retries on all platforms at the moment:
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe install
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe install
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe install

exitIfFailed

C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe build

exitIfFailed
