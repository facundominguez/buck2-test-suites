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

  fixGrapesy = hfinal: hprev: {
    crypton-x509 = hprev.crypton-x509_1_8_0;
    crypton-x509-store = hprev.crypton-x509-store_1_8_0;
    crypton-x509-system = hprev.crypton-x509-system_1_8_0;
    crypton-x509-validation = hprev.crypton-x509-validation_1_8_0;
    grapesy = final.haskell.lib.compose.overrideCabal (old: {
      src = (final.fetchgit {
        url = "https://github.com/well-typed/grapesy.git";
        # master
        rev = "bd6af64f69ff89e3a8fc02e2c81262e648f4715d";
        sha256 = "sha256-4F+bUoytvrgOcQ8aIWbOY9uYsPoTZwQOlmh7ckgyK9M=";
      }) + "/grapesy";
    }) hprev.grapesy;
    http-semantics = hprev.http-semantics_0_4_0;
    http2 = hprev.http2_5_4_0;
    http2-tls = final.haskell.lib.compose.unmarkBroken hprev.http2-tls;
    network-run = hprev.network-run_0_5_0;
    tls = hprev.tls_2_2_1;
  };

  # for fixed nodes
  patchDoctest = hfinal: hprev: {
    doctest = final.haskell.lib.compose.overrideCabal (drv: {
      src = final.applyPatches {
        src = hprev.doctest.src;
        patches = [ ./haskell-patches/doctest-fixed_nodes-adjustment.patch ];
      };
      doCheck = false;
    }) hprev.doctest;
    #inspection-testing = final.haskell.lib.compose.dontCheck hprev.inspection-testing;
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
    fixGrapesy
    patchDoctest
    patchLiquidHaskell
  ];
in
makeHaskellOverlay (lib.composeManyExtensions allHaskellOverlays)
