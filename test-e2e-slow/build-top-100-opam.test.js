// @flow

const {
  createSandbox,
  mkdirTemp,
  setup,
  ocamlVersion,
  esyPrefixPath,
} = require('./setup.js');
const fs = require('fs');
const path = require('path');
const rmSync = require('rimraf').sync;
const isCi = require('is-ci');

const cases = [
  {name: 'ocamlfind', toolchains: [ocamlVersion]},
  {name: 'jbuilder', toolchains: [ocamlVersion]},
  {name: 'cppo', toolchains: [ocamlVersion]},
  {name: 'result', toolchains: [ocamlVersion]},
  {name: 'ocamlbuild', toolchains: [ocamlVersion]},
  {name: 'topkg', toolchains: [ocamlVersion]},
  {name: 'ocaml-migrate-parsetree', toolchains: [ocamlVersion]},
  {name: 'menhir', toolchains: [ocamlVersion]},
  {name: 'camlp5', toolchains: [ocamlVersion]},
  {name: 'ppx_tools_versioned', toolchains: [ocamlVersion]},
  {name: 'yojson', toolchains: [ocamlVersion]},
  {name: 'biniou', toolchains: [ocamlVersion]},
  {name: 'easy-format', toolchains: [ocamlVersion]},
  {name: 'lwt', toolchains: [ocamlVersion]},
  {name: 'sexplib', toolchains: [ocamlVersion]},
  {name: 'ppx_type_conv', toolchains: [ocamlVersion]},
  {name: 'ppx_driver', toolchains: [ocamlVersion]},
  {name: 'ppx_core', toolchains: [ocamlVersion]},
  {name: 'camlp4', toolchains: [ocamlVersion]},
  {name: 'cmdliner', toolchains: [ocamlVersion]},
  {name: 'ppx_sexp_conv', toolchains: [ocamlVersion]},
  {name: 'ppx_optcomp', toolchains: [ocamlVersion]},
  {name: 'ppx_tools', toolchains: [ocamlVersion]},
  {name: 'ounit', toolchains: [ocamlVersion]},
  {name: 'stdio', toolchains: [ocamlVersion]},
  {name: 'base', toolchains: [ocamlVersion]},
  {name: 'ppx_ast', toolchains: [ocamlVersion]},
  {name: 'ocaml-compiler-libs', toolchains: [ocamlVersion]},
  {name: 'ppx_metaquot', toolchains: [ocamlVersion]},
  {name: 'ppx_traverse_builtins', toolchains: [ocamlVersion]},
  {name: 'ppx_deriving', toolchains: [ocamlVersion]},
  {name: 'ppx_fields_conv', toolchains: [ocamlVersion]},
  {name: 'fieldslib', toolchains: [ocamlVersion]},
  {name: 're', toolchains: [ocamlVersion]},
  {name: 'ppx_compare', toolchains: [ocamlVersion]},
  {name: 'camomile', toolchains: [ocamlVersion]},
  {name: 'react', toolchains: [ocamlVersion]},
  {name: 'cppo_ocamlbuild', toolchains: [ocamlVersion]},
  {name: 'ppx_enumerate', toolchains: [ocamlVersion]},
  {name: 'xmlm', toolchains: [ocamlVersion]},
  {name: 'configurator', toolchains: [ocamlVersion]},
  {name: 'bin_prot', toolchains: [ocamlVersion]},
  {name: 'conf-libcurl', toolchains: [ocamlVersion]},
  {name: 'core_kernel', toolchains: [ocamlVersion]},
  {name: 'zed', toolchains: [ocamlVersion]},
  {name: 'lambda-term', toolchains: [ocamlVersion]},
  {name: 'zarith', toolchains: [ocamlVersion]},
  {name: 'ppx_hash', toolchains: [ocamlVersion]},
  {name: 'core', toolchains: [ocamlVersion]},
  {name: 'ppx_variants_conv', toolchains: [ocamlVersion]},
  {name: 'ppx_custom_printf', toolchains: [ocamlVersion]},
  {name: 'ppx_base', toolchains: [ocamlVersion]},
  {name: 'utop', toolchains: [ocamlVersion]},
  {name: 'octavius', toolchains: [ocamlVersion]},
  {name: 'variantslib', toolchains: [ocamlVersion]},
  {name: 'ppx_bin_prot', toolchains: [ocamlVersion]},
  {name: 'ppx_js_style', toolchains: [ocamlVersion]},
  {name: 'uchar', toolchains: [ocamlVersion]},
  {name: 'ppx_expect', toolchains: [ocamlVersion]},
  {name: 'ppx_here', toolchains: [ocamlVersion]},
  {name: 'ppx_assert', toolchains: [ocamlVersion]},
  {name: 'ppx_typerep_conv', toolchains: [ocamlVersion]},
  {name: 'ppx_sexp_value', toolchains: [ocamlVersion]},
  {name: 'ppx_sexp_message', toolchains: [ocamlVersion]},
  {name: 'typerep', toolchains: [ocamlVersion]},
  {name: 'ppx_inline_test', toolchains: [ocamlVersion]},
  {name: 'lwt_react', toolchains: [ocamlVersion]},
  {name: 'ppx_let', toolchains: [ocamlVersion]},
  {name: 'ppx_fail', toolchains: [ocamlVersion]},
  {name: 'ppx_bench', toolchains: [ocamlVersion]},
  {name: 'ppx_pipebang', toolchains: [ocamlVersion]},
  {name: 'ppx_derivers', toolchains: [ocamlVersion]},
  {name: 'base64', toolchains: [ocamlVersion]},
  {name: 'ppx_traverse', toolchains: [ocamlVersion]},
  {name: 'ppx_jane', toolchains: [ocamlVersion]},
  {name: 'uutf', toolchains: [ocamlVersion]},
  {name: 'ocp-build', toolchains: [ocamlVersion]},
  {name: 'merlin', toolchains: [ocamlVersion]},
  {name: 'ppx_optional', toolchains: [ocamlVersion]},
  {name: 'oasis', toolchains: [ocamlVersion]},
  {name: 'uri', toolchains: [ocamlVersion]},
  {name: 'cryptokit', toolchains: [ocamlVersion]},
  {name: 'jane-street-headers', toolchains: [ocamlVersion]},
  {name: 'stringext', toolchains: [ocamlVersion]},
  {name: 'spawn', toolchains: [ocamlVersion]},
  {name: 'ocamlmod', toolchains: [ocamlVersion]},
  {name: 'ocamlify', toolchains: [ocamlVersion]},
  {name: 'ipaddr', toolchains: [ocamlVersion]},
  {name: 'depext', toolchains: [ocamlVersion]},
  {name: 'fmt', toolchains: [ocamlVersion]},
  {name: 'cohttp', toolchains: [ocamlVersion]},
  {name: 'num', toolchains: [ocamlVersion]},
  {name: 'cstruct', toolchains: [ocamlVersion]},
  {name: 'logs', toolchains: [ocamlVersion]},
  {name: 'ctypes', toolchains: [ocamlVersion]},
  {name: 'astring', toolchains: [ocamlVersion]},
  {name: 'bisect_ppx', toolchains: [ocamlVersion]},
  {name: 'jsonm', toolchains: [ocamlVersion]},
  {name: 'async_unix', toolchains: [ocamlVersion]},
  {name: 'async_extra', toolchains: [ocamlVersion]},
  {name: 'async', toolchains: [ocamlVersion]},
  {name: 'cudf', toolchains: [ocamlVersion]},
  {name: 'dose3', toolchains: [ocamlVersion]},
  {name: 'ssl', toolchains: [ocamlVersion]},
  {name: 'tls', toolchains: [ocamlVersion]},
];

let reposUpdated = false;

function shuffle(array) {
  array = array.slice(0);
  let counter = array.length;

  while (counter > 0) {
    let index = Math.floor(Math.random() * counter);

    counter--;

    let temp = array[counter];
    array[counter] = array[index];
    array[index] = temp;
  }

  return array;
}

const startTime = new Date();
const runtimeLimit = 17 * 60 * 1000;

setup();

for (let c of shuffle(cases)) {
  for (let toolchain of c.toolchains) {
    const nowTime = new Date();
    if (isCi && nowTime - startTime > runtimeLimit) {
      console.log(`*** Exiting earlier ***`);
      break;
    }

    console.log(`*** building ${c.name} with ocaml@${toolchain} ***`);

    const sandbox = createSandbox();
    console.log(`*** sandbox.path: ${sandbox.path}`);

    const packageJson = {
      name: `test-${c.name}`,
      version: '0.0.0',
      esy: {build: ['true']},
      dependencies: {
        ['@opam/' + c.name]: '*',
      },
      devDependencies: {
        ocaml: toolchain,
      },
    };

    fs.writeFileSync(
      path.join(sandbox.path, 'package.json'),
      JSON.stringify(packageJson, null, 2),
    );

    let install = [`install`];
    if (reposUpdated) {
      install = ['install', '--skip-repository-update'];
    } else {
      reposUpdated = true;
    }

    sandbox.esy(...install);
    sandbox.esy('build');

    rmSync(path.join(esyPrefixPath, '3', 'b'));
    sandbox.dispose();
  }
}
