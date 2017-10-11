# Integration test suite for `esy release` command

Run with (from the `<PROJECT_ROOT>/esy`):

    % ./node_modules/jest ./__tests__/release/*-test.js

You can also run tests in debug mode:

    % DEBUG=yes ./node_modules/jest ./__tests__/release/release-dev-minimal-test.js

It's important you run only a single test case at a time in debug mode. See
instructions printed on screen on how to introspect the test state.
