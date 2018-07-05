# Windows initial test script
# This is just a VERY basic test exercising `esy install` and `esy build` for a canonical project:
# `esy-reason-project`
#
# This should be removed once we have the windows build hooked up to our existing test suite

Write-Host "Cloning test repo.."
git clone https://github.com/esy-ocaml/esy-reason-project C:/erp
Write-Host "Clone complete!"
cd C:/erp
ls

mkdir C:/esy-home
$env:HOME=C:/esy-home
C:/projects/esy/_release/_build/default/esy/bin/esyCommand.exe install
