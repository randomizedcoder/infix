# nix/apps/default.nix
#
# Commands that read the live tree or the network, so they run with `nix run`:
#
#   vulncheck     govulncheck per Go module + osv-scanner over the lock files
#   secrets-scan  gitleaks over the git history
#   deps-drift    the pins in ../deps/pins.nix against Buildroot's .mk files
#
# deps-drift is also a `nix flake check`, against the flake's buildroot input.

{ pkgs, lib, infixLib, versions, buildroot }:

let
  pins = import ../deps/pins.nix;

  pinsFile = pkgs.writeText "infix-pins" ''
    buildroot package/libyang/libyang.mk LIBYANG_VERSION ${pins.libyang.version}
    buildroot package/sysrepo/sysrepo.mk SYSREPO_VERSION ${pins.sysrepo.version}
    infix package/faux/faux.mk FAUX_VERSION ${pins.faux.rev}
    infix package/klish/klish.mk KLISH_VERSION ${pins.klish.rev}
  '';

  drift = pkgs.writeShellApplication {
    name = "infix-deps-drift";
    runtimeInputs = with pkgs; [ coreutils gnused git ];
    text = builtins.readFile ./deps-drift.sh;
  };

  # The files deps-drift reads, so the check reruns only when they change.
  driftSrc = lib.fileset.toSource {
    inherit (infixLib) root;
    fileset = lib.fileset.unions [
      (infixLib.root + "/package/faux/faux.mk")
      (infixLib.root + "/package/klish/klish.mk")
      (infixLib.root + "/patches")
    ];
  };
in
{
  apps = {
    vulncheck = pkgs.writeShellApplication {
      name = "vulncheck";
      runtimeInputs = [ versions.go versions.govulncheck versions.osv-scanner pkgs.gnugrep pkgs.gnused ];
      runtimeEnv.GO_MODULES = toString infixLib.goModules;
      text = builtins.readFile ./vulncheck.sh;
    };

    secrets-scan = pkgs.writeShellApplication {
      name = "secrets-scan";
      runtimeInputs = [ versions.gitleaks pkgs.jq ];
      text = builtins.readFile ./secrets-scan.sh;
    };

    # deps-drift [infix-root]: against the buildroot submodule when it is checked out.
    deps-drift = pkgs.writeShellApplication {
      name = "deps-drift";
      runtimeEnv.BUILDROOT_REV = buildroot.rev;
      text = ''
        root=''${1:-.}
        br=$root/buildroot
        [ -f "$br/package/libyang/libyang.mk" ] || br=${buildroot}
        exec ${lib.getExe drift} "$root" "$br" ${pinsFile}
      '';
    };
  };

  checks.deps-drift = pkgs.runCommand "infix-deps-drift" { } ''
    ${lib.getExe drift} ${driftSrc} ${buildroot} ${pinsFile} | tee "$out"
  '';
}
