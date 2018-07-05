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
