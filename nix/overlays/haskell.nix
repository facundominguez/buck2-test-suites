# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

final: prev:
let
  inherit (prev) lib;

  ghcVer = final.mercury.compilerName;

  makeHaskellOverlay = overlay: {
    haskell = prev.haskell // {
      packages = prev.haskell.packages // {
        ${ghcVer} = prev.haskell.packages."${ghcVer}".override (oldArgs: {
          overrides = prev.lib.composeExtensions (oldArgs.overrides or (_: _: { })) overlay;
        });
      };
    };
  };

  # FIXME(jadel): maybe we should upstream this to nixpkgs, maybe we should eliminate it altogether.
  # https://github.com/NixOS/nixpkgs/pull/501773
  fixPackageDB = hfinal: hprev: {
    mkDerivation =
      args:
      let
        isExecutable = args.isExecutable or false;
        isLibrary = args.isLibrary or (!isExecutable);
      in
      hprev.mkDerivation (
        args
        // {
          postInstall =
            lib.optionalString isLibrary ''
              ghc-pkg --package-db="$packageConfDir" recache
            ''
            + (args.postInstall or "");
        }
      );
  };

  # Patch liquidhaskell-boot for Mercury-patched GHC 9.10.3.
  # The Mercury GHC patches remove mi_globals, move HomePackageTable,
  # change lookupHpt to IO, add CompressionIFace param to putWithUserData,
  # add UnitIndexQuery param to renamePkgQual, and add Eq (VarBndr) instance.
  patchLiquidHaskell = hfinal: hprev: {
    liquidhaskell-boot = hprev.liquidhaskell-boot.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../overlays/haskell-patches/liquidhaskell-boot-ghc9103.patch
        ../overlays/haskell-patches/liquidhaskell-boot-plugin-package.patch
      ];
    });

    liquidhaskell = hprev.liquidhaskell.overrideAttrs (old: {
      # LiquidHaskell self-hosts: it uses itself as a GHC plugin during
      # compilation of its own _LHAssumptions modules, which invokes z3.
      buildInputs = (old.buildInputs or [ ]) ++ [ final.z3 ];
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.z3 ];
    });
  };

  allHaskellOverlays = [
    fixPackageDB
    patchLiquidHaskell
  ];
in
makeHaskellOverlay (lib.composeManyExtensions allHaskellOverlays)
