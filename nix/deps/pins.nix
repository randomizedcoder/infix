# nix/deps/pins.nix
#
# Versions read by nix/deps and compared with the tree by the deps-drift check.
{
  # buildroot/package/libyang/libyang.mk
  libyang = {
    version = "6.4.13";
    hash = "sha256-kykfPU7tGkPY2nYKGDDiOwKpheNvsnDST9bX7nCpKzM=";
  };
  # buildroot/package/sysrepo/sysrepo.mk
  sysrepo = {
    version = "5.2.27";
    hash = "sha256-JBt5+ozHNiPW7iy5GpSWiPsqs8XzSBrAY00bh5TFYrM=";
  };
  # package/faux/faux.mk
  faux = {
    rev = "df1d569287bc45d8fd880287c00e3874c5627c19";
    hash = "sha256-y1GFCZvnAJqsdWLxLnvolDBuXl4dAnC5dcqF47OJka4=";
  };
  # package/klish/klish.mk
  klish = {
    rev = "5880300b23ea7378a4af186d510a61be64dfd630";
    hash = "sha256-90byEOEUuzhn7ar3JSBxUyenPX6U/RS6LzioHHkeY5E=";
  };
}
