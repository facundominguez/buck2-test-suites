# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

{ ... }:
let
  lockFile = builtins.fromJSON (builtins.readFile ../nix/flake.lock);
  flake-compat-node = lockFile.nodes.${lockFile.nodes.root.inputs.flake-compat};
  flake-compat = builtins.fetchTarball {
    inherit (flake-compat-node.locked) url;
    sha256 = flake-compat-node.locked.narHash;
  };

  nixpkgs-node = lockFile.nodes.nixpkgs;
  nixpkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgs-node.locked.rev}.tar.gz";
    sha256 = nixpkgs-node.locked.narHash;
  }) { };

  flake = (
    import flake-compat {
      src = ../nix;
      copySourceTreeToStore = false;
    }
  );

  system = builtins.currentSystem;
  inherit (flake.outputs.legacyPackages.${system}) pkgs hsPkgs;
in
pkgs.mkShell {
  nativeBuildInputs = [
    nixpkgs.cabal-install
    hsPkgs.ghc
    pkgs.protobuf
    pkgs.snappy
    pkgs.zlib
  ];
}
