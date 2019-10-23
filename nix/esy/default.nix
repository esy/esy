# nix-build -E 'with import <nixpkgs> { }; import ./esy pkgs'
pkgs: with pkgs;

let
  esyVersion = "0.5.8";

  ocamlPackages = pkgs.ocamlPackages.overrideScope' (self: super: rec {
    cmdliner = pkgs.ocamlPackages.cmdliner.overrideDerivation (old: {
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
    buildInputs = with ocamlPackages; [
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
    deps = with ocamlPackages; [
      ocamlgraph
      re
      cppo
    ];
  };

  opam-format = opam-lib {
    pname = "opam-format";
    deps = with ocamlPackages; [
      opam-file-format
      opam-core
    ];
  };

  opam-repository = opam-lib {
    pname = "opam-repository";
    deps = with ocamlPackages; [
      opam-format
    ];
  };

  opam-state = opam-lib {
    pname = "opam-state";
    deps = with ocamlPackages; [
      opam-repository
    ];
  };

  cudf = stdenv.mkDerivation rec {
    name = "cudf";
    buildInputs = with ocamlPackages; [
      ocaml
      ocamlbuild
      # for pod2man
      perl
      findlib
    ];
    propagatedBuildInputs = with ocamlPackages; [ ocaml_extlib ];
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
    buildInputs = with ocamlPackages; [
      ocaml
      findlib
      ocamlbuild
      ocaml_extlib
      cudf
      ocamlgraph
      cppo
      re
      perl
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

  esy-solve-cudf = ocamlPackages.buildDunePackage rec {
    pname = "esy-solve-cudf";
    version = "0.1.10";
    buildInputs = with ocamlPackages; [
      ocaml
      findlib
      dune
      ocaml_extlib
    ];
    propagatedBuildInputs = with ocamlPackages; [ cmdliner cudf ];
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

  esyNpm = builtins.fetchurl {
    url = "https://registry.npmjs.org/esy/${esyVersion}";
    sha256 = "0rhbbg7rav68z5xwppx1ni8gjm6pcqf564nn1z6yrag3wgjgs63c";
  };

  esySolveCudfNpm = builtins.fetchurl {
    url = "https://registry.npmjs.org/esy-solve-cudf/${esy-solve-cudf.version}";
    sha256 = "19m793mydd8gcgw1mbn7pd8fw2rhnd00k5wpa4qkx8a3zn6crjjf";
  };

in
  ocamlPackages.buildDunePackage rec {
    pname = "esy";
    version = "0.5.8";

    minimumOCamlVersion = "4.06";

    src = fetchFromGitHub {
      owner  = "esy";
      repo   = pname;
      rev    = "v${version}";
      sha256 = "0n2606ci86vqs7sm8icf6077h5k6638909rxyj43lh55ah33l382";
    };

    propagatedBuildInputs = with ocamlPackages; [
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
  postBuild = "true";

  meta = {
    homepage = https://github.com/esy/esy;
    description = "package.json workflow for native development with Reason/OCaml";
    license = stdenv.lib.licenses.bsd2;
    # maintainers = with stdenv.lib.maintainers; [ sternenseemann ];
  };
}
