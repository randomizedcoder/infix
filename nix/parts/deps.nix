# nix/parts/deps.nix
#
# The pinned libraries (../deps): libyang, sysrepo, faux, klish.

{
  perSystem = { infix, ... }: {
    packages = { inherit (infix) libyang sysrepo faux klish; };
  };
}
