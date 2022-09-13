{
  pkgs,
  esy,
}:
pkgs.buildFHSUserEnv {
  name = "esy";
  targetPkgs = pkgs: (with pkgs; [
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

    # Do we need this?
    glib.dev
    gmp
    gnum4
    linuxHeaders
    pkgconfig
    unzip
    which
    nodePackages.npm
    nodejs
  ]);
  runScript = "${esy}/bin/esy";
}
