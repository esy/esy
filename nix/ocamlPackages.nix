{
  ocamlPackages,
  fetchFromGitLab,
}:
ocamlPackages.overrideScope' (self: super: rec {
  alcotest = super.alcotest.overrideAttrs (_: {
    src = builtins.fetchurl {
      url = https://github.com/mirage/alcotest/releases/download/1.4.0/alcotest-mirage-1.4.0.tbz;
      sha256 = "1h9yp44snb6sgm5g1x3wg4gwjscic7i56jf0j8jr07355pxwrami";
    };
  });

  cmdliner = super.cmdliner.overrideAttrs (_: {
    src = builtins.fetchurl {
      url = https://github.com/esy-ocaml/cmdliner/archive/e9316bc.tar.gz;
      sha256 = "1g0shk5ahc6byhx79ry6vdyf89a1ncq5bsgykkxa05xabvlr09ji";
    };
    createFindlibDestdir = true;
  });

  fmt = super.fmt.overrideAttrs (_: {
    src = builtins.fetchurl {
      url = https://github.com/dbuenzli/fmt/archive/refs/tags/v0.8.10.tar.gz;
      sha256 = "0xnnrhp45p5vj1wzjn39w0j29blxrqj2dn42qcxzplp2j9mn76b9";
    };
  });

  uuidm = super.uuidm.overrideAttrs (_: {
    src = builtins.fetchurl {
      url = "https://erratique.ch/software/uuidm/releases/uuidm-0.9.7.tbz";
      sha256 = "1ivxb3hxn9bk62rmixx6px4fvn52s4yr1bpla7rgkcn8981v45r8";
    };
  });

  menhirLib = super.menhirLib.overrideAttrs (_: {
    version = "20211012";
    src = fetchFromGitLab {
      domain = "gitlab.inria.fr";
      owner = "fpottier";
      repo = "menhir";
      rev = "20211012";
      sha256 = "sha256-gHw9LmA4xudm6iNPpop4VDi988ge4pHZFLaEva4qbiI=";
    };
  });
})
