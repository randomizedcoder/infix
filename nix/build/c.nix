# nix/build/c.nix
#
# Host builds of the C components under src/, the way Buildroot configures them but
# with every feature flag on, so the analysis and the sanitizer builds see all the
# code.  Each component is its own derivation; libsrx is a dependency of the rest.
#
#   infix-c         every component (release, -O2)
#   infix-c-debug   -O0 -g3
#   infix-c-asan    AddressSanitizer + UndefinedBehaviorSanitizer, clang
#   infix-c-cov     gcov instrumentation
#   <name>          one component, e.g. confd, statd, libsrx
#
# buildC (passed on to the analysis and compile-db) builds one component with
# extra attributes.

{ pkgs
, lib
, infixLib
, versions
, libyang
, sysrepo
, klish
, faux
}:

let
  variants = {
    release = { };
    # _FORTIFY_SOURCE needs optimization; at -O0 it is a warning, an error under -Werror.
    debug = { NIX_CFLAGS_COMPILE = "-O0 -g3"; hardeningDisable = [ "fortify" ]; dontStrip = true; };
    asan = {
      stdenv = versions.llvm.stdenv;
      # clang warns where gcc does not; the analysis reports those, the build goes on.
      NIX_CFLAGS_COMPILE = "-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wno-error";
      NIX_CFLAGS_LINK = "-fsanitize=address,undefined";
      hardeningDisable = [ "fortify" ];
      dontStrip = true;
    };
    cov = { NIX_CFLAGS_COMPILE = "-O0 -g --coverage"; NIX_CFLAGS_LINK = "--coverage"; hardeningDisable = [ "fortify" ]; dontStrip = true; };
  };

  # What each component needs beyond libsrx, and the flags it is configured with.
  components = {
    # configure.ac checks for nothing, but the headers include all three.
    libsrx = { inputs = [ ]; propagated = with pkgs; [ libite libyang sysrepo ]; };
    confd = {
      inputs = with pkgs; [ libxcrypt glib jansson libite libyang sysrepo sysklogd watchdogd openssl libev ];
      flags = [
        "--enable-containers"
        "--enable-frr"
        "--enable-wifi"
        "--enable-gps"
        "--enable-console"
        "--enable-netbrowse"
        "--enable-webui"
        "--enable-snmp"
        "--enable-netconf-subsystem"
      ];
    };
    statd = {
      # Makefile.am links -lz without a configure check, and journal_retention_stub -static.
      inputs = with pkgs; [ jansson libite libyang sysrepo avahi libev zlib ];
      # The sanitizer runtimes cannot link -static, so the asan stub is dynamic.
      preBuild = variant:
        if variant == "asan" then ''
          makeFlagsArray+=("journal_retention_stub_LDFLAGS=")
        '' else ''
          makeFlagsArray+=("journal_retention_stub_LDFLAGS=-static -L${pkgs.glibc.static}/lib")
        '';
      flags = [ "--enable-containers" "--enable-frr" ];
    };
    netd = {
      inputs = with pkgs; [ libite libconfuse jansson libev ];
      flags = [ "--with-frr-conf" ];
    };
    bin = { inputs = with pkgs; [ libite libyang sysrepo ]; };
    klish-plugin-infix = {
      inputs = with pkgs; [ libyang sysrepo klish faux ];
      flags = [ "--enable-containers" "--enable-snmp" "--enable-shell" ];
    };
    gencert = { inputs = [ pkgs.openssl ]; };
    rauc-installation-status = { inputs = with pkgs; [ glib jansson ]; };
    test-mode = { inputs = with pkgs; [ sysrepo pkgs.libite libyang ]; };
    # Plain Makefiles, no autotools.
    # RESETME_PATH as Buildroot sets it for a non-DDI image (package/factory/factory.mk).
    factory = { inputs = [ ]; plain = true; cflags = "-DRESETME_PATH=/mnt/cfg/infix.reset"; };
    keyack = { inputs = [ ]; plain = true; };
  };

  # buildC variant name extra: one component.  `extra` is merged last, so the
  # analysis can swap in its own buildPhase (bear, scan-build, -fanalyzer).
  buildC = variant: name: extra:
    let
      c = components.${name};
      v = variants.${variant};
      stdenv = v.stdenv or pkgs.stdenv;
      plain = c.plain or false;
      srx = if name == "libsrx" then [ ] else [ (libsrxFor variant) ];
    in
    stdenv.mkDerivation ({
      pname = "infix-${name}${lib.optionalString (variant != "release") "-${variant}"}";
      inherit (infixLib) version;
      src = infixLib.srcFor name;
      sourceRoot = "source/src/${name}";
      nativeBuildInputs = [ pkgs.pkg-config ] ++ lib.optional (!plain) pkgs.autoreconfHook;
      buildInputs = c.inputs ++ srx;
      propagatedBuildInputs = c.propagated or [ ];
      configureFlags = (c.flags or [ ]) ++ [
        "--disable-silent-rules"
        # Install sysrepo plugins into $out, not into the read-only sysrepo package.
        "srpdplugindir=${placeholder "out"}/lib/sysrepo-plugind/plugins"
      ];
      makeFlags = lib.optionals plain [ "DESTDIR=${placeholder "out"}" ];
      preBuild = (c.preBuild or (_: "")) variant;
      # Their `install -D <file> sbin/` needs the directory to exist.
      preInstall = lib.optionalString plain "mkdir -p $out/sbin";
      enableParallelBuilding = true;
      # nixpkgs hardening adds _FORTIFY_SOURCE, which makes unchecked system() and
      # chdir() results errors under the components' -Werror; keep them warnings.
      NIX_CFLAGS_COMPILE = toString [ "-Wno-error=unused-result" (v.NIX_CFLAGS_COMPILE or "") (c.cflags or "") ];
      passthru = { inherit name variant; };
      inherit (infixLib) meta;
    } // removeAttrs v [ "stdenv" "NIX_CFLAGS_COMPILE" ] // extra);

  libsrxFor = variant: buildC variant "libsrx" { };

  names = lib.attrNames components;
  forVariant = variant: lib.genAttrs names (n: buildC variant n { });
  join = variant: pkgs.symlinkJoin {
    name = "infix-c${lib.optionalString (variant != "release") "-${variant}"}";
    paths = lib.attrValues (forVariant variant);
  };

  release = forVariant "release";
in
{
  inherit buildC components names;
  byVariant = lib.genAttrs (lib.attrNames variants) forVariant;

  packages = release // {
    infix-c = join "release";
    infix-c-debug = join "debug";
    infix-c-asan = join "asan";
    infix-c-cov = join "cov";
  };
  checks = { infix-c = join "release"; };
}
