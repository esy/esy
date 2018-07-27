// @flow

const child_process = require('child_process');
const fs = require('fs');
const path = require('path');
const rmSync = require('rimraf').sync;

const cases = [
  {name: "ocamlfind", toolchains: ["~4.6.0"]},
  {name: "jbuilder", toolchains: ["~4.6.0"]},
  {name: "cppo", toolchains: ["~4.6.0"]},
  {name: "result", toolchains: ["~4.6.0"]},
  {name: "ocamlbuild", toolchains: ["~4.6.0"]},
  {name: "topkg", toolchains: ["~4.6.0"]},
  {name: "ocaml-migrate-parsetree", toolchains: ["~4.6.0"]},
  {name: "menhir", toolchains: ["~4.6.0"]},
  {name: "camlp5", toolchains: ["~4.6.0"]},
  {name: "ppx_tools_versioned", toolchains: ["~4.6.0"]},
  {name: "yojson", toolchains: ["~4.6.0"]},
  {name: "biniou", toolchains: ["~4.6.0"]},
  {name: "easy-format", toolchains: ["~4.6.0"]},
  {name: "lwt", toolchains: ["~4.6.0"]},
  {name: "sexplib", toolchains: ["~4.6.0"]},
  {name: "ppx_type_conv", toolchains: ["~4.6.0"]},
  {name: "ppx_driver", toolchains: ["~4.6.0"]},
  {name: "ppx_core", toolchains: ["~4.6.0"]},
  {name: "camlp4", toolchains: ["~4.6.0"]},
  {name: "cmdliner", toolchains: ["~4.6.0"]},
  {name: "ppx_sexp_conv", toolchains: ["~4.6.0"]},
  {name: "ppx_optcomp", toolchains: ["~4.6.0"]},
  {name: "ppx_tools", toolchains: ["~4.6.0"]},
  {name: "ounit", toolchains: ["~4.6.0"]},
  {name: "stdio", toolchains: ["~4.6.0"]},
  {name: "base", toolchains: ["~4.6.0"]},
  {name: "ppx_ast", toolchains: ["~4.6.0"]},
  {name: "ocaml-compiler-libs", toolchains: ["~4.6.0"]},
  {name: "ppx_metaquot", toolchains: ["~4.6.0"]},
  {name: "ppx_traverse_builtins", toolchains: ["~4.6.0"]},
  {name: "ppx_deriving", toolchains: ["~4.6.0"]},
  {name: "ppx_fields_conv", toolchains: ["~4.6.0"]},
  {name: "fieldslib", toolchains: ["~4.6.0"]},
  {name: "re", toolchains: ["~4.6.0"]},
  {name: "ppx_compare", toolchains: ["~4.6.0"]},
  {name: "camomile", toolchains: ["~4.6.0"]},
  {name: "react", toolchains: ["~4.6.0"]},
  {name: "cppo_ocamlbuild", toolchains: ["~4.6.0"]},
  {name: "ppx_enumerate", toolchains: ["~4.6.0"]},
  {name: "xmlm", toolchains: ["~4.6.0"]},
  {name: "configurator", toolchains: ["~4.6.0"]},
  {name: "bin_prot", toolchains: ["~4.6.0"]},
  {name: "core_kernel", toolchains: ["~4.6.0"]},
  {name: "zed", toolchains: ["~4.6.0"]},
  {name: "lambda-term", toolchains: ["~4.6.0"]},
  {name: "zarith", toolchains: ["~4.6.0"]},
  {name: "ppx_hash", toolchains: ["~4.6.0"]},
  {name: "core", toolchains: ["~4.6.0"]},
  {name: "ppx_variants_conv", toolchains: ["~4.6.0"]},
  {name: "ppx_custom_printf", toolchains: ["~4.6.0"]},
  {name: "ppx_base", toolchains: ["~4.6.0"]},
  {name: "utop", toolchains: ["~4.6.0"]},
  {name: "octavius", toolchains: ["~4.6.0"]},
  {name: "variantslib", toolchains: ["~4.6.0"]},
  {name: "ppx_bin_prot", toolchains: ["~4.6.0"]},
  {name: "ppx_js_style", toolchains: ["~4.6.0"]},
  {name: "uchar", toolchains: ["~4.6.0"]},
  {name: "ppx_expect", toolchains: ["~4.6.0"]},
  {name: "ppx_here", toolchains: ["~4.6.0"]},
  {name: "ppx_assert", toolchains: ["~4.6.0"]},
  {name: "ppx_typerep_conv", toolchains: ["~4.6.0"]},
  {name: "ppx_sexp_value", toolchains: ["~4.6.0"]},
  {name: "ppx_sexp_message", toolchains: ["~4.6.0"]},
  {name: "typerep", toolchains: ["~4.6.0"]},
  {name: "ppx_inline_test", toolchains: ["~4.6.0"]},
  {name: "lwt_react", toolchains: ["~4.6.0"]},
  {name: "ppx_let", toolchains: ["~4.6.0"]},
  {name: "ppx_fail", toolchains: ["~4.6.0"]},
  {name: "ppx_bench", toolchains: ["~4.6.0"]},
  {name: "ppx_pipebang", toolchains: ["~4.6.0"]},
  {name: "ppx_derivers", toolchains: ["~4.6.0"]},
  {name: "base64", toolchains: ["~4.6.0"]},
  {name: "ppx_traverse", toolchains: ["~4.6.0"]},
  {name: "ppx_jane", toolchains: ["~4.6.0"]},
  {name: "uutf", toolchains: ["~4.6.0"]},
  {name: "ocp-build", toolchains: ["~4.6.0"]},
  {name: "merlin", toolchains: ["~4.6.0"]},
  {name: "ppx_optional", toolchains: ["~4.6.0"]},
  {name: "oasis", toolchains: ["~4.6.0"]},
  {name: "uri", toolchains: ["~4.6.0"]},
  {name: "cryptokit", toolchains: ["~4.6.0"]},
  {name: "jane-street-headers", toolchains: ["~4.6.0"]},
  {name: "stringext", toolchains: ["~4.6.0"]},
  {name: "spawn", toolchains: ["~4.6.0"]},
  {name: "ocamlmod", toolchains: ["~4.6.0"]},
  {name: "ocamlify", toolchains: ["~4.6.0"]},
  {name: "ipaddr", toolchains: ["~4.6.0"]},
  {name: "depext", toolchains: ["~4.6.0"]},
  {name: "fmt", toolchains: ["~4.6.0"]},
  {name: "cohttp", toolchains: ["~4.6.0"]},
  {name: "num", toolchains: ["~4.6.0"]},
  {name: "cstruct", toolchains: ["~4.6.0"]},
  {name: "logs", toolchains: ["~4.6.0"]},
  {name: "ctypes", toolchains: ["~4.6.0"]},
  {name: "astring", toolchains: ["~4.6.0"]},
  {name: "bisect_ppx", toolchains: ["~4.6.0"]},
  {name: "jsonm", toolchains: ["~4.6.0"]},
  {name: "async_unix", toolchains: ["~4.6.0"]},
  {name: "async_extra", toolchains: ["~4.6.0"]},
  {name: "async", toolchains: ["~4.6.0"]},
  {name: "cudf", toolchains: ["~4.6.0"]},
  {name: "dose3", toolchains: ["~4.6.0"]},
  {name: "ssl", toolchains: ["~4.6.0"]},
  {name: "tls", toolchains: ["~4.6.0"]},
];

const esyPrefixPath = fs.mkdtempSync('/tmp/esy-prefix');

let reposUpdated = false;

for (let c of cases) {

  for (let toolchain of c.toolchains) {

    console.log(`*** building ${c.name} with ocaml@${toolchain} ***`);

    const sandboxPath = fs.mkdtempSync('/tmp/esy-project');
    console.log(`*** sandboxPath: ${sandboxPath}`)

    const esy = path.join(__dirname, '..', 'bin', 'esy');

    const packageJson = {
      name: `test-${c.name}`,
      version: '0.0.0',
      esy: {build: ['true']},
      dependencies: {
        ['@opam/' + c.name]: "*"
      },
      devDependencies: {
        ocaml: toolchain
      }
    };

    fs.writeFileSync(
      path.join(sandboxPath, 'package.json'),
      JSON.stringify(packageJson, null, 2)
    );

    let installCommand = `${esy} install`;
    if (reposUpdated) {
      installCommand = `${esy} install --skip-repository-update`;
    } else {
      reposUpdated = true;
    }

    child_process.execSync(installCommand, {
      cwd: sandboxPath,
      env: {...process.env, ESY__PREFIX: esyPrefixPath},
      stdio: 'inherit',
    });

    child_process.execSync(`${esy} build`, {
      cwd: sandboxPath,
      env: {...process.env, ESY__PREFIX: esyPrefixPath},
      stdio: 'inherit',
    });

    rmSync(path.join(esyPrefixPath, '3', 'b'));
    rmSync(sandboxPath);
  }

}

rmSync(esyPrefixPath);
