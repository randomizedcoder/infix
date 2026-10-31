# nix/lib/default.nix
#
# infixLib: what the builds, analysis and fuzzing share.
#
#   version, meta   for every Infix derivation.  The version leaves out the git
#                   revision, or every commit would rebuild everything.
#   srcFor <dir>    one directory under src/ (plus a Go module's local replaces), so
#                   editing confd does not rebuild webui.
#   src.c           every C component under src/, for the analysis tools.
#   src.yang        src/confd/yang, for yanglint and the libyang-based harnesses.
#   src.all         the tracked tree, for the whole-tree linters.

{ lib }:

let
  root = ../..;
  inherit (lib) fileset;

  # Generated or local files that must not leak into a source from a dev checkout.
  junk = fileset.fileFilter
    (f: lib.any f.hasExt [ "o" "lo" "la" "a" "so" ]
      || lib.elem f.name [ "config.status" "config.log" "Makefile.in" "configure" ])
    root;
  clean = fs: fileset.difference fs (fileset.intersection junk fs);

  cDirs = [
    "bin"
    "confd"
    "factory"
    "gencert"
    "keyack"
    "klish-plugin-infix"
    "libsrx"
    "netd"
    "rauc-installation-status"
    "statd"
    "test-mode"
  ];
  goModules = [ "webui" "yangerd" "netbrowse" "features" ];
in
{
  inherit root cDirs goModules;
  version = "0-unstable";

  # webui and yangerd replace github.com/kernelkit/infix/src/features with ../features.
  srcFor = dir: fileset.toSource {
    inherit root;
    fileset = clean (fileset.unions (map (d: root + "/src/${d}")
      ([ dir ] ++ lib.optional (lib.elem dir [ "webui" "yangerd" ]) "features")));
  };

  src = {
    c = fileset.toSource {
      inherit root;
      fileset = clean (fileset.unions (map (d: root + "/src/${d}") cDirs ++ [ (root + "/src/.clang-format") ]));
    };
    yang = fileset.toSource { inherit root; fileset = root + "/src/confd/yang"; };
    all = fileset.toSource { inherit root; fileset = clean (fileset.gitTracked root); };
  };

  meta = {
    homepage = "https://github.com/kernelkit/infix";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
