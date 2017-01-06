const {createTestEnv} = require('../harness');

let sandbox = createTestEnv({sandbox: __dirname});

sandbox.exec(`
pushd PackageC
popd

pushd PackageB
rm -rf node_modules
mkdir node_modules
cd node_modules
ln -s ../../PackageC ./PackageC
popd

pushd PackageA
rm -rf node_modules
mkdir node_modules
cd node_modules
ln -s ../../PackageC ./PackageC
ln -s ../../PackageB ./PackageB
popd
`);

test('environment for PackageC', () => {
  let res = sandbox.exec(`
  cd PackageC
  ../../../.bin/esy
  `);
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
});

test('environment for PackageB', () => {
  let res = sandbox.exec(`
  cd PackageB
  ../../../.bin/esy
  `);
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
});

test('environment for PackageA', () => {
  let res = sandbox.exec(`
  cd PackageA
  ../../../.bin/esy
  `);
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
});
