# find ~/.esy -name "*wasm*" -exec rm -rf {} +
esy
esy release
cd _release
npm pack
npm install --prefix /tmp/esy esy-0.6.10.tgz
# export PATH="/tmp/esy/node_modules/esy/bin:$PATH"
# Add a dune target when build 