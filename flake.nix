{
  inputs = {
    nixpkgs.url = "github:nix-ocaml/nix-overlays";
    nixpkgs.inputs.flake-utils.follows = "flake-utils";

    flake-utils.url = "github:numtide/flake-utils";

    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nix-filter,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        esy-solve-cudf = pkgs.callPackage ./nix/esy-solve-cudf.nix {};
        esy = pkgs.callPackage ./nix {inherit nix-filter esy-solve-cudf;};
        fhs = pkgs.callPackage ./nix/fhs.nix {inherit esy;};
      in {
        packages = {
          default = fhs;
          inherit esy esy-solve-cudf fhs;
        };
        devShells = {
          default = self.packages."${system}".fhs.env;
        };
      }
    );
}
