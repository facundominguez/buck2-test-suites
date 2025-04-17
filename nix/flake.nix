{
  description = "Providing toolchain dependencies via flake";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ghc-persistent-worker = {
      url = "path:REPLACE_ME";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ghc-persistent-worker,
    }@input':
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlay-ghc = import ./overlay-ghc.nix;
        overlay-haskell-packages = import ./overlay-haskell-packages.nix { input = input'; };

        pkgs = import nixpkgs {
          inherit system;
          config.allowBroken = true;
          overlays = [
            overlay-ghc
            overlay-haskell-packages
          ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt-rfc-style
          ];

          shellHook = ''
            export PS1="\n[buck2-test-suites:\w]$ \0"
          '';
        };
        packages = {
          buck-worker = pkgs.haskell.packages.ghc9101.buck-worker;
          buck-multiplex-worker = pkgs.haskell.packages.ghc9101.buck-multiplex-worker;
        };
      }
    );
}
