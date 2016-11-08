cd ../
pushd PackageC && rm -r node_modules && popd && pushd PackageB && rm -r node_modules && popd && pushd PackageA && rm -r node_modules

cd ../PackageC && npm install && npm link && cd ../PackageB && npm link PackageC && npm install && npm link && cd ../PackageA && npm link PackageC && npm link PackageB && npm install

../../../.bin/esy
