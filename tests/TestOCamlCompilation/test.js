const {createTestEnv} = require('../harness');

let sandbox = createTestEnv({
  sandbox: __dirname
});

sandbox.exec(`
pushd buildtool
rm -rf node_modules
npm install
popd

pushd PackageC
rm -rf node_modules
mkdir node_modules
pushd node_modules
ln -s ../../buildtool ./buildtool
popd
npm install
popd

pushd PackageB
rm -rf node_modules
mkdir node_modules
pushd node_modules
ln -s ../../buildtool ./buildtool
ln -s ../../PackageC ./PackageC
popd
npm install
popd

pushd PackageA
rm -rf node_modules
mkdir node_modules
pushd node_modules
ln -s ../../buildtool ./buildtool
ln -s ../../PackageC ./PackageC
ln -s ../../PackageB ./PackageB
popd
npm install
popd
`);

test('env', () => {
  let res = sandbox.exec(`
  rm -rf _esy_store
  cd PackageA
  rm -rf _build _install
  ../../../.bin/esy
  `);
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
});

test('build', () => {
  let res = sandbox.exec(`
  rm -rf _esy_store
  cd PackageA
  rm -rf _build _install
  ../../../.bin/esy build
  `);
  expect(res.status).toBe(0);
  expect(res.stdout.toString()).toMatchSnapshot();
  let output = sandbox.exec(`
  cd PackageA
  ../../../.bin/esy ocamlrun ./_build/package_a_cmd
  `);
  expect(output.status).toBe(0);
  expect(output.stdout.toString()).toMatchSnapshot();
});
