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

npm run test-e2e

exitIfFailed

# Run slow-e2e tests if necessary

$shouldRunTest = 0
if ($env:APPVEYOR_REPO_COMMIT_MESSAGE) {
    $isCommitTagSet = $env:APPVEYOR_REPO_COMMIT_MESSAGE.Contains("@slowtest")

    if ($isCommitTagSet) {
        Write-Host "@slowtest set; running slow tests."
        $shouldRunTest = 1
    } else {
        Write-Host "@slowtest not set"
    }
} elseif ($env:APPVEYOR_REPO_TAG) {
    Write-Host "Tag was pushed; running slow tests."
    $shouldRunTest = 1
}

if ($shouldRunTest) {
    Write-Host "Running slow tests..."

    # Not passing yet on Windows, hold off on this one
    # node test-e2e/build-top-100-opam.slowtest.js
    # exitIfFailed

    node test-e2e/install-npm.slowtest.js
    exitIfFailed
} else {
    Write-Host "Skipped slow tests."
}
