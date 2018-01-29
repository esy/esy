#!/bin/bash

set -e
set -u
set -o pipefail

ocamlrun=$(node -p 'require.resolve("@esy-ocaml/ocamlrun/install/bin/ocamlrun")')
version=$(node -p 'require("./package.json").version')

cat <<EOF > ./bin/esy
#!/bin/bash
ESY__VERSION="${version}" ${ocamlrun} ${PWD}/bin/esy.bc "\$@"
EOF

chmod +x ./bin/esy

(cd bin && node ./esy.js autoconf > ./esyConfig.sh)
