# nix-build -E  \
#   'with import <nixpkgs> { };
#    let esy = callPackage ./nix/esy{};
#    in
#    callPackage esy {
#      githubInfo = {
#        owner = "anmonteiro";
#        rev= "2f40f56";
#        sha256="0bn2p5ac1nsmbb0yxb3sq75kd25003k5qgikjyafkvhmlgh03xih";
#      };
#      npmInfo = {
#        url = "https://registry.npmjs.org/@esy-nightly/0.6.0-8b3dfe";
#        sha256 = "0rhbbg7rav68z5xwppx1ni8gjm6pcqf564nn1z6yrag3wgjgs63c";
#      };
#    }' \
#  --pure

{ stdenv, fetchFromGitHub, ocamlPackages, opaline, perl }:

let
  currentVersion = "0.5.8";

  currentGithubInfo = {
    owner = "esy";
    rev    = "v${currentVersion}";
    sha256 = "0n2606ci86vqs7sm8icf6077h5k6638909rxyj43lh55ah33l382";
  };

in

{ githubInfo ? currentGithubInfo, version ? currentVersion }:

let
  esyVersion = version;

  esyOcamlPkgs = ocamlPackages.overrideScope' (self: super: {
    cmdliner = super.cmdliner.overrideDerivation (old: {
      src = builtins.fetchurl {
        url = https://github.com/esy-ocaml/cmdliner/archive/8500634a96019c4d29b1751628025b693f2b97d6.tar.gz;
        sha256 = "094s12xzlywglfjs95gam47bq3is72zkaz3082zq8s4gi1w2irva";
      };
      createFindlibDestdir = true;
    });
  });

  opam-lib = { pname, deps }: stdenv.mkDerivation rec {
    name = pname;
    version = "2.0.5";
    buildInputs = with esyOcamlPkgs; [
      ocaml
      findlib
      dune
    ];
    propagatedBuildInputs = deps;
    src = fetchFromGitHub {
      owner  = "ocaml";
      repo   = "opam";
      rev    = "${version}";
      sha256 = "0pf2smq2sdcxryq5i87hz3dv05pb3zasb1is3kxq1pi1s4cn55mx";
    };
    configurePhase = ''
      ./configure --disable-checks
    '';
    buildPhase = ''
      make ${name}.install
    '';
    installPhase = ''
      runHook preInstall
      ${opaline}/bin/opaline -prefix $out -libdir $OCAMLFIND_DESTDIR
      runHook postInstall
    '';
  };

  opam-core = opam-lib {
    pname= "opam-core";
    deps = with esyOcamlPkgs; [
      ocamlgraph
      re
      cppo
    ];
  };

  opam-format = opam-lib {
    pname = "opam-format";
    deps = with esyOcamlPkgs; [
      opam-file-format
      opam-core
    ];
  };

  opam-repository = opam-lib {
    pname = "opam-repository";
    deps = with esyOcamlPkgs; [
      opam-format
    ];
  };

  opam-state = opam-lib {
    pname = "opam-state";
    deps = with esyOcamlPkgs; [
      opam-repository
    ];
  };

  cudf = stdenv.mkDerivation rec {
    name = "cudf";
    buildInputs = with esyOcamlPkgs; [
      ocaml
      ocamlbuild
      # for pod2man
      perl
      findlib
    ];
    propagatedBuildInputs = with esyOcamlPkgs; [ ocaml_extlib ];
    src = builtins.fetchTarball {
      url = https://gforge.inria.fr/frs/download.php/36602/cudf-0.9.tar.gz;
      sha256 = "12p8aap34qsg1hcjkm79ak3n4b8fm79iwapi1jzjpw32jhwn6863";
    };
    buildPhase = ''
      make all opt
    '';
    patchPhase = "sed -i s@/usr/@$out/@ Makefile.config";
    createFindlibDestdir = true;
  };

  dose3 = stdenv.mkDerivation {
    name = "dose";
    src = builtins.fetchurl {
      url = "http://gforge.inria.fr/frs/download.php/file/36063/dose3-5.0.1.tar.gz";
      sha256 = "00yvyfm4j423zqndvgc1ycnmiffaa2l9ab40cyg23pf51qmzk2jm";
    };
    buildInputs = with esyOcamlPkgs; [
      ocaml
      findlib
      ocamlbuild
      cppo
      perl
    ];
    propagatedBuildInputs = with esyOcamlPkgs; [
      cudf
      ocaml_extlib
      ocamlgraph
      re
    ];
    createFindlibDestdir = true;
    patches = [
      ./patches/0001-Install-mli-cmx-etc.patch
      ./patches/0002-dont-make-printconf.patch
      ./patches/0003-Fix-for-ocaml-4.06.patch
      ./patches/0004-Add-unix-as-dependency-to-dose3.common-in-META.in.patch
      ./patches/dose.diff
    ];
  };

  esy-solve-cudf = esyOcamlPkgs.buildDunePackage rec {
    pname = "esy-solve-cudf";
    version = "0.1.10";
    buildInputs = with esyOcamlPkgs; [
      ocaml
      findlib
      dune
    ];
    propagatedBuildInputs = with esyOcamlPkgs; [
      cmdliner
      cudf
      ocaml_extlib
    ];
    src = fetchFromGitHub {
      owner  = "andreypopp";
      repo   = pname;
      rev    = "v${version}";
      sha256 = "174q1wkr31dn8vsvnlj4hzfgvbamqq74n7wxhbccriqmv8lz5a3g";
      fetchSubmodules = true;
    };

    buildPhase = ''
      runHook preBuild
      dune build -p ${pname},mccs
      runHook postBuild
    '';

    meta = {
      homepage = https://github.com/andreypopp/esy-solve-cudf;
      description = "package.json workflow for native development with Reason/OCaml";
      license = stdenv.lib.licenses.gpl3;
    };
  };

  # XXX(anmonteiro): The NPM registry doesn't allow us to fetch version
  # information for scoped packages, and `@esy-nightly/esy` is scoped. It also
  # seems that Esy only uses the `package.json` file to display the version
  # information in `esy --version`, so we can kinda ignore this for now. We're
  # able to build and install nightly releases but it'll always display the
  # current version information.
  esyNpm = builtins.fetchurl {
    url = "https://registry.npmjs.org/esy/${esyVersion}";
    sha256 = "0rhbbg7rav68z5xwppx1ni8gjm6pcqf564nn1z6yrag3wgjgs63c";
  };

  esySolveCudfNpm = builtins.fetchurl {
    url = "https://registry.npmjs.org/esy-solve-cudf/${esy-solve-cudf.version}";
    sha256 = "19m793mydd8gcgw1mbn7pd8fw2rhnd00k5wpa4qkx8a3zn6crjjf";
  };

in
  esyOcamlPkgs.buildDunePackage rec {
    pname = "esy";
    version = esyVersion;

    minimumOCamlVersion = "4.06";

    src = fetchFromGitHub {
      owner  = githubInfo.owner;
      repo   = pname;
      rev    = githubInfo.rev;
      sha256 = githubInfo.sha256;
    };

    propagatedBuildInputs = with esyOcamlPkgs; [
      angstrom
      cmdliner
      reason
      bos
      fmt
      fpath
      lambdaTerm
      logs
      lwt4
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
    runHook preBuild
    dune build -p ${pname},esy-build-package
    runHook postBuild
  '';

  # |- bin
  #   |- esy
  # |- lib
  #   |- default
  #     |- bin
  #       |- esy.exe
  #       |- esyInstallRelease.js
  #     |- esy-build-package
  #       |- bin
  #       |- esyBuildPackageCommand.exe
  #       |- esyRewritePrefixCommand.exe
  #   |- node_modules
  #     |- esy-solve-cudf
  #       |- package.json
  #       |- esySolveCudfCommand.exe
  fixupPhase = ''
    mkdir -p $out/lib/default/bin
    mkdir -p $out/lib/default/esy-build-package/bin
    mkdir -p $out/lib/node_modules/esy-solve-cudf
    mv $out/bin/esy $out/lib/default/bin/esy.exe
    mv $out/bin/esyInstallRelease.js $out/lib/default/bin/
    mv $out/bin/esy-build-package $out/lib/default/esy-build-package/bin/esyBuildPackageCommand.exe
    mv $out/bin/esy-rewrite-prefix $out/lib/default/esy-build-package/bin/esyRewritePrefixCommand.exe
    ln -s $out/lib/default/bin/esy.exe $out/bin/esy
    cp ${esyNpm} $out/package.json
    cp ${esySolveCudfNpm} $out/lib/node_modules/esy-solve-cudf/package.json
    cp ${esy-solve-cudf}/bin/esy-solve-cudf $out/lib/node_modules/esy-solve-cudf/esySolveCudfCommand.exe

  '';

  meta = {
    homepage = https://github.com/esy/esy;
    description = "package.json workflow for native development with Reason/OCaml";
    license = stdenv.lib.licenses.bsd2;
  };
}
