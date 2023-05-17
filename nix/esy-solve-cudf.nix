{
  pkgs,
  lib,
  fetchFromGitHub,
  stdenv,
}: let
  ocamlPackages = pkgs.callPackage ./ocamlPackages.nix {};
in
  with ocamlPackages;
    stdenv.mkDerivation rec {
      pname = "esy-solve-cudf";
      version = "0.1.10";

      src = fetchFromGitHub {
        owner = "andreypopp";
        repo = pname;
        rev = "v${version}";
        sha256 = "1ky2mkyl676bxphyx0d3vqr58za185nq46h0lai89631g94ia1d7";
      };

      buildInputs = [
        ocaml
        findlib
        dune
      ];
      propagatedBuildInputs = [
        cmdliner
        cudf
        mccs
        ocaml_extlib
      ];

      buildPhase = ''
        runHook preBuild
        dune build -p ${pname}
        runHook postBuild
      '';

      installPhase = ''
        dune install --prefix $out
      '';

      meta = {
        homepage = https://github.com/andreypopp/esy-solve-cudf;
        description = "package.json workflow for native development with Reason/OCaml";
        license = lib.licenses.gpl3;
      };
    }
