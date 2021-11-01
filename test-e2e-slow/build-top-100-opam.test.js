// @flow

const {
  createSandbox,
  mkdirTemp,
  setup,
  ocamlVersion,
  esyPrefixPath,
} = require('./setup.js');
const fs = require('fs');
const os = require('os');
const path = require('path');
const rmSync = require('rimraf').sync;
const isCi = require('is-ci');

let cases = [
   { name: "menhir", toolchains: [ocamlVersion] },
   { name: "csexp", toolchains: [ocamlVersion] },
   { name: "atd", toolchains: [ocamlVersion] },
   { name: "dot-merlin-reader", toolchains: [ocamlVersion] },
   // TODO: it's looking for X11 on mac's Needs esy-libx11 and/or esy-xquartz
   // { name: "graphics", toolchains: [ocamlVersion] },
   { name: "stdlib-shims", toolchains: [ocamlVersion] },
   { name: "js_of_ocaml", toolchains: [ocamlVersion] },
   { name: "ppx_tools_versioned", toolchains: [ocamlVersion] },
   { name: "ppx_deriving_yojson", toolchains: [ocamlVersion] },
   { name: "ppx_cold", toolchains: [ocamlVersion] },
   { name: "zarith", toolchains: [ocamlVersion] },
   { name: "sexplib0", toolchains: [ocamlVersion] },
   { name: "cohttp", toolchains: [ocamlVersion] },
   { name: "decoders", toolchains: [ocamlVersion] },
   { name: "ocamlformat", toolchains: [ocamlVersion] },
   { name: "jsonrpc", toolchains: [ocamlVersion] },
   { name: "conduit", toolchains: [ocamlVersion] },
   { name: "ctypes", toolchains: [ocamlVersion] },
   { name: "reason", toolchains: [ocamlVersion] },
   // TODO @opam/mccs@opam:1.1+13 fails on macos
   // { name: "opam-client", toolchains: [ocamlVersion] },
   { name: "ocamlbuild", toolchains: [ocamlVersion] },
   { name: "ocamlgraph", toolchains: [ocamlVersion] },
   { name: "junit", toolchains: [ocamlVersion] },
   { name: "result", toolchains: [ocamlVersion] },
   { name: "time_now", toolchains: [ocamlVersion] },
   { name: "ppx_yojson_conv_lib", toolchains: [ocamlVersion] },
   { name: "ounit", toolchains: [ocamlVersion] },
   { name: "utop", toolchains: [ocamlVersion] },
   { name: "opam-depext", toolchains: [ocamlVersion] },
   { name: "elpi", toolchains: [ocamlVersion] },
   { name: "biniou", toolchains: [ocamlVersion] },
   { name: "ppx_deriving", toolchains: [ocamlVersion] },
   { name: "printbox", toolchains: [ocamlVersion] },
   { name: "bos", toolchains: [ocamlVersion] },
   { name: "lwt", toolchains: [ocamlVersion] },
   { name: "psq", toolchains: [ocamlVersion] },
   { name: "ppx_tools", toolchains: [ocamlVersion] },
   { name: "ppx_inline_test", toolchains: [ocamlVersion] },
   { name: "yojson", toolchains: [ocamlVersion] },
   { name: "ocamlfind", toolchains: [ocamlVersion] },
   { name: "ppx_string", toolchains: [ocamlVersion] },
   { name: "ppx_fixed_literal", toolchains: [ocamlVersion] },
   { name: "merlin", toolchains: [ocamlVersion] },
   { name: "ppxfind", toolchains: [ocamlVersion] },
   // TODO { name: "camlp5", toolchains: [ocamlVersion] },
   { name: "semver2", toolchains: [ocamlVersion] },
   { name: "magic-mime", toolchains: [ocamlVersion] },
   // TODO fails to build on macos arm64
   // { name: "coq", toolchains: [ocamlVersion] },
   { name: "sedlex", toolchains: [ocamlVersion] },
   { name: "dune", toolchains: [ocamlVersion] },
   { name: "cmdliner", toolchains: [ocamlVersion] },
   { name: "charInfo_width", toolchains: [ocamlVersion] },
   // TODO needs esy-cairo
   // { name: "lablgtk3", toolchains: [ocamlVersion] },
   { name: "jbuilder", toolchains: [ocamlVersion] },
   { name: "sexplib", toolchains: [ocamlVersion] },
   { name: "opam-file-format", toolchains: [ocamlVersion] },
   { name: "pcre", toolchains: [ocamlVersion] },
   { name: "irmin", toolchains: [ocamlVersion] },
   { name: "base64", toolchains: [ocamlVersion] },
   { name: "timezone", toolchains: [ocamlVersion] },
   { name: "batteries", toolchains: [ocamlVersion] },
   { name: "ca-certs", toolchains: [ocamlVersion] },
   { name: "duration", toolchains: [ocamlVersion] },
   { name: "oasis", toolchains: [ocamlVersion] },
   { name: "git", toolchains: [ocamlVersion] },
   { name: "core_kernel", toolchains: [ocamlVersion] },
   { name: "camlzip", toolchains: [ocamlVersion] },
   { name: "fix", toolchains: [ocamlVersion] },
   // TODO Works only with opam by default { name: "alt-ergo", toolchains: [ocamlVersion] },
   { name: "lsp", toolchains: [ocamlVersion] },
   { name: "bisect_ppx", toolchains: [ocamlVersion] },
   { name: "ppx_fields_conv", toolchains: [ocamlVersion] },
   { name: "ff", toolchains: [ocamlVersion] },
   { name: "ocp-indent", toolchains: [ocamlVersion] },
   { name: "core", toolchains: [ocamlVersion] },
   { name: "ANSITerminal", toolchains: [ocamlVersion] },
   // TODO
   // { name: "mad", toolchains: [ocamlVersion] },
   // Needs esy-lame
   // { name: "lame", toolchains: [ocamlVersion] },
   { name: "parmap", toolchains: [ocamlVersion] },
   { name: "extlib", toolchains: [ocamlVersion] },
   { name: "lwt_log", toolchains: [ocamlVersion] },
   { name: "cry", toolchains: [ocamlVersion] },
   // TODO needs esy-vorbis
   // { name: "vorbis", toolchains: [ocamlVersion] },
   { name: "grain_dypgen", toolchains: [ocamlVersion] },
   // TODO needs esy-samplerate
   // { name: "samplerate", toolchains: [ocamlVersion] },
   // TODO needs esy-taglib
   // { name: "taglib", toolchains: [ocamlVersion] },
   { name: "ppx_sexp_conv", toolchains: [ocamlVersion] },
   { name: "calendar", toolchains: [ocamlVersion] },
   { name: "merlin-extend", toolchains: [ocamlVersion] },
   { name: "num", toolchains: [ocamlVersion] },
   { name: "xml-light", toolchains: [ocamlVersion] },
   { name: "tyxml", toolchains: [ocamlVersion] },
   { name: "yaml", toolchains: [ocamlVersion] },
   { name: "awa", toolchains: [ocamlVersion] },
   { name: "uuidm", toolchains: [ocamlVersion] },
   { name: "mirage", toolchains: [ocamlVersion] },
   { name: "cppo", toolchains: [ocamlVersion] },
   { name: "sqlite3", toolchains: [ocamlVersion] },
   // TODO { name: "ppx_has", toolchains: [ocamlVersion] },
   // Blocked by esy/esy#505
   // {name: 'coq', toolchains: [ocamlVersion]},
   { name: 'libtorch', toolchains: [ocamlVersion] },
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

function selectCases(array) {
  // Start with a subset on windows...
  return os.platform() == 'win32' ? shuffle(array.slice(0, 10)) : shuffle(array);
}

const startTime = new Date();
const runtimeLimit = 60 * 60 * 1000;

setup();

for (let c of selectCases(cases)) {
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
