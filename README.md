Test suites for Buck2
=====================

Configuration to test various buck repositories. This configuration provides
nix environment to run `buck2` and a few toolchains.

# buck2-haskell

To test `buck2-haskell` run

```
git clone https://github.com/MercuryTechnologies/buck2-haskell
nix-shell --run "buck test buck2-haskell//tests/..."
```
