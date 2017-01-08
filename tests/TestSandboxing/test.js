const {createTestEnv} = require('../harness');

// For now sandboxing is only supported on macOS.
if (process.platform === 'darwin') {

  let sandbox = createTestEnv({
    sandbox: __dirname,
    esyTest: false
  });

  test('catches violation (darwin)', () => {
    let res = sandbox.execAndExpectFailure(`
    rm -rf _build _install _esy_store
    ../../.bin/esy build`
    );
    expect(res.status).not.toBe(0);
    expect(sandbox.readFile('node_modules', 'should_be_GOOD')).toBe('GOOD');
  });

}

test('just some dummy case so jest does not fail on unsupported platforms', () => {});
