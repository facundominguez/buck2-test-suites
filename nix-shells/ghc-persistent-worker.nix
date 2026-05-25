# Standalone nix-shell providing the same GHC compiler as `nix develop ghc-persistent-worker/`.
# Usage: nix-shell ghc-persistent-worker.nix

{ ... }:
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/b2243f41e860ac85c0b446eadc6930359b294e79.tar.gz";
    sha256 = "sha256-M4ilIfGxzbBZuURokv24aqJTbdjPA9K+DtKUzrJaES4=";
  };

  pkgs = import nixpkgs {};

  # Custom GHC 9.10.1 built from the MWB branch commit, matching `compilers.mwb-26-01-ipe` in
  # ghc-persistent-worker/flake.nix. Uses nixpkgs' Hadrian builder directly.
  # xattr and autoSignDarwinBinariesHook are Darwin-only; they are lazily evaluated by
  # common-hadrian.nix so passing the darwin-scoped packages is safe on Linux.
  ghc = pkgs.callPackage
    (import "${nixpkgs}/pkgs/development/compilers/ghc/common-hadrian.nix" {
      version = "9.10.1";
      rev     = "65d1ec83348e10082f60a4ae400cbcd31f76ad05";
      sha256  = "sha256-mUnXDm708rVZH9wiglOUZ6bnS83Aln6ik+r2uTfDoP0=";
      url     = "https://gitlab.haskell.org/ghc/ghc";
    })
    {
      bootPkgs               = pkgs.haskell.packages.ghc963Binary;
      inherit (pkgs.darwin) xattr autoSignDarwinBinariesHook;
      buildTargetLlvmPackages = pkgs.llvmPackages_19;
      llvmPackages            = pkgs.llvmPackages_19;
      ghcFlavour              = "release+split_sections+ipe";
    };

in
pkgs.mkShell {
  packages = [
    pkgs.libz
    pkgs.cabal-install
    pkgs.snappy
    pkgs.protobuf
    ghc
  ];
}
