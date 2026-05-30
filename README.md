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

To test `ghc-persistent-worker` run

```
git clone https://github.com/MercuryTechnologies/ghc-persistent-worker
nix-shell nix-shells/ghc-persistent-worker.nix --run "cabal test --enable-tests -fmwb all"
```
