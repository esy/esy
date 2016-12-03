cd ../
pushd PackageC && rm -rf node_modules && popd && \
pushd PackageB && rm -rf node_modules && popd && \
pushd buildtool && rm -rf node_modules && popd && \
pushd PackageA && rm -rf node_modules

cd ../buildtool && npm install && npm link && \
cd ../PackageC && npm link buildtool && npm install && npm link && \
cd ../PackageB && npm link buildtool && npm link PackageC && npm install && npm link && \
cd ../buildtool && npm install && npm link && \
cd ../PackageA && npm link PackageC && npm link PackageB && npm link buildtool && npm install

../../../.bin/esy $1
