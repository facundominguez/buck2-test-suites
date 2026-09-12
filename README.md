Test suites for Buck2
=====================

Configuration to test various buck repositories. This configuration provides
nix environment to run `buck2` and a few toolchains.

### buck2-haskell

To test `buck2-haskell` clone the repo

```
git clone https://github.com/MercuryTechnologies/buck2-haskell
```

For local execution testing, run

```
nix-shell --run "buck test buck2-haskell//tests/...
```

For sandboxed execution testing, first build and run `nativelink` with the
provided configuration:

```
nix run github:TraceMachina/nativelink/v1.3.2 -- ./nativelink.config.json5 > /tmp/nativelink.log 2>&1 &
```

Then copy the configuration in `.buckconfig.local.nativelink` to
`.buckconfig.local`, and then run the tests with

```
nix-shell --run "buck test buck2-haskell//tests/... --config execution_platform=platforms//:re
```

### ghc-persistent-worker

The persistent worker is built and run as part of the `buck2-haskell` tests.

### Testing with a locally built GHC

You can run the test with a GHC that is compatible with the haskell library
binaries that buck2-test-suite sets. Thus, is relatively easy to test changes
on the GHC compiler that `buck2-test-suite` uses. If the haskell libraries
needed recompilation, then other measures would be necessary.

First build GHC, and then replace the `toolchains//:ghc` target with

    impure_binary(
        name = "ghc",
        binary_path = "path/to/your/ghc",
    )

    impure_binary(
        name = "ghc-pkg",
        binary_path = "path/to/your/ghc-pkg",
    )

    impure_binary(
        name = "haddock",
        binary_path = "path/to/your/haddock",
    )

Also edit `toolchains/nix/nix_haskell_toolchain.bzl` to use these targets.

    --- a/toolchains/nix/nix_haskell_toolchain.bzl
    +++ b/toolchains/nix/nix_haskell_toolchain.bzl
    @@ -296,11 +296,11 @@ nix_haskell_toolchain = rule(
             ),
             "ghc_pkg": attrs.dep(
                 providers = [RunInfo],
    -            default = "//:ghc[ghc-pkg]",
    +            default = "//:ghc-pkg",
             ),
             "haddock": attrs.dep(
                 providers = [RunInfo],
    -            default = "//:ghc[haddock]",
    +            default = "//:haddock",
             ),
             "flake": attrs.source(allow_directory = True),
         },

Also build the toolchain libraries with the locally built GHC,

    nix-shell -p libz snappy --run "\
    cabal \
      --store-dir=/path/to/store \
      install \
      --with-compiler=path/to/your/ghc \
      --lib \
      --package-env=- \
      aeson async flatparse ghc ghc-paths grapesy hashable lens-family optparse-applicative proto-lens split vector \
      "

then declare the toolchain libraries with

    haskell_toolchain_library_from_package_db(
        name = "toolchain_libs",
        package_db = "/path/to/store/store/ghc-9.10.3-be79/package.db",
    )

then run the tests with

    nix-shell -p libz snappy --run "buck test buck2-haskell//tests/build_tests/worker/..."
