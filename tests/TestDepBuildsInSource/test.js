const {createTestEnv} = require('../harness');

let sandbox = createTestEnv({
  sandbox: __dirname
});

test('env', () => {
  let res = sandbox.exec('../../.bin/esy');
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
});

test('forces build to happen in $cur__target_dir', () => {
  let res = sandbox.exec(`
  rm -rf _build _install _esy_store
  ../../.bin/esy build
  `);
  expect(res.status).toBe(0);
  expect(sandbox.readFile('node_modules', 'dep', 'OK')).toBe('OK');
  expect(sandbox.readFile('_esy_store', '_build', 'dep-1.0.0', 'OK')).toBe('OK!!!');
});
