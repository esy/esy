# Ignore failures for the first two 'esy install' runs
# This works around windows-specific issues with intermittency in failing esy install
esy install
esy install

# For the last run, we'll check the exit code and fail if it failed
esy install

if ($LastExitCode -ne 0) {
    exit $LastExitCode
}
