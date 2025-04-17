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
        pkgs = import nixpkgs {
          inherit system;
          config.allowBroken = true;
          overlays = [
            (self: super: {
              haskell = super.haskell // {
                packages = super.haskell.packages // {
                  ghc9101 = super.haskell.packages.ghc9101.override (prev: {
                    overrides = self.lib.composeExtensions (prev.overrides or (_: _: { })) (
                      import ./overlay.nix {
                        input = input';
                        pkgs = self;
                      }
                    );
                  });
                };
              };
            })
          ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            #hsenv
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
