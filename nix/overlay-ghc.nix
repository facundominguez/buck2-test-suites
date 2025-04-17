self: super:

let
  ghc9101Src = self.fetchFromGitHub {
    owner = "MercuryTechnologies";
    repo = "ghc";
    # branch: mercury-ghc9101
    rev = "2c4d9f6151898e1da7721d39e0ef30bdfb0b9e44";
    hash = "sha256-sTSEiKRRS9+n4M/mI9IbBvmcahGynVksoWlEH/OMzJQ=";
    fetchSubmodules = true;
  };

in

{
  haskell = super.haskell // {
    compiler = super.haskell.compiler // {
      ghc9101 =
        (super.haskell.compiler.ghc9101.override {
          ghcSrc = ghc9101Src;
        }).overrideAttrs
          (drv: {
            # Regenerate `configure` from `configure.ac`.
            postPatch = ''
              ${self.python3}/bin/python boot
              ${self.autoconf}/bin/autoreconf --force --install --include=m4
            '';

          });
    };
  };
}
