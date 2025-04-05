{
  pkgs,
  lib,
  nix-filter,
  stdenv,
  bash,
  binutils,
  coreutils,
  makeWrapper,
  esy-solve-cudf,
}: let
  esyOcamlPkgs = pkgs.callPackage ./ocamlPackages.nix {};
in
  with esyOcamlPkgs;
    stdenv.mkDerivation {
      pname = "esy";
      version = "0.6.14";

      src = with nix-filter.lib;
        filter {
          root = ../.;
          include = [
            "bin"
            "esy-version"
            "esy-build"
            "esy-build-package"
            "esy-command-expression"
            "esy-fetch"
            "esy-install"
            "esy-install-npm-release"
            "esy-lib"
            "esy-package-config"
            "esy-primitives"
            "esy-shell-expansion"
            "esy-solve"
            "fastreplacestring"
            "flow-typed"
            "scripts"
            "dune"
            "dune-project"
            "dune-workspace"
            "esy.opam"
            "esy.opam.locked"
          ];
        };

      nativeBuildInputs = [
        makeWrapper
        dune-configurator
        dune
        ocaml
        findlib
      ];

      propagatedBuildInputs = [
        coreutils
        bash
      ];

      buildInputs = [
        angstrom
        cmdliner
        reason
        bos
        fmt
        fpath
        lambda-term
        logs
        lwt
        lwt_ppx
        menhir
        opam-file-format
        ppx_deriving
        ppx_deriving_yojson
        ppx_expect
        ppx_inline_test
        ppx_let
        ppx_sexp_conv
        re
        yojson
        cudf
        dose3
        opam-format
        opam-core
        opam-state
      ];
      doCheck = false;

      buildPhase = ''
        dune build -p esy
      '';

      installPhase = ''
        dune install --prefix $out
        mkdir -p $out/lib/esy
        ln -s ${esy-solve-cudf}/bin/esy-solve-cudf $out/lib/esy/esySolveCudfCommand
        ls $out/lib/esy

        wrapProgram "$out/bin/esy" \
          --prefix PATH : ${lib.makeBinPath (with pkgs; [
          binutils
          coreutils
          esy
          curl
          git
          perl
          gnumake
          gnupatch
          gcc
          bash
        ])}
      '';

      meta = {
        homepage = https://github.com/esy/esy;
        description = "package.json workflow for native development with Reason/OCaml";
        license = lib.licenses.bsd2;
      };
    }
