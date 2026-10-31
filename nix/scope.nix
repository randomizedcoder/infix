# nix/scope.nix
#
# Every Infix derivation, in one package scope (lib.makeScope).  Each file is called
# with callPackage, so it names what it needs and gets it from this scope first,
# then from nixpkgs.  The flake-parts modules in parts/ read their outputs from here:
#
#   infix = import ./scope.nix { inherit pkgs inputs; };
#   infix.cPkgs.packages.confd

{ pkgs, inputs }:

pkgs.lib.makeScope pkgs.newScope (self: {
  infixLib = self.callPackage ./lib { };
  versions = import ./versions.nix {
    inherit pkgs;
    pkgsStable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  };

  # Buildroot at the submodule's commit, for the sysrepo patches (flake.nix input).
  inherit (inputs) buildroot;
  deps = self.callPackage ./deps { };
  inherit (self.deps) libyang sysrepo faux klish;

  # Each of these returns { packages, checks?, apps? } for a part in parts/.
  cPkgs = self.callPackage ./build/c.nix { };
  goPkgs = self.callPackage ./build/go.nix { };
  compileDb = self.callPackage ./build/compile-db.nix { };
  analysisPkgs = self.callPackage ./analysis { };
  fuzzPkgs = self.callPackage ./fuzz { };
  dev = self.callPackage ./dev { };
})
