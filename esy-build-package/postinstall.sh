set -u
set -e
set -o pipefail

OCAMLRUN=$(node -p 'require.resolve("@esy-ocaml/ocamlrun/install/bin/ocamlrun")')

echo "#!$OCAMLRUN" > ./esyb
cat esyb.bc >> ./esyb
chmod +x ./esyb
