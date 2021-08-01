esy
esy release
cd _release
npm pack
npm install --prefix /tmp/esy esy-$(esy version).tgz
# export PATH="/tmp/esy/node_modules/esy/bin:$PATH" 