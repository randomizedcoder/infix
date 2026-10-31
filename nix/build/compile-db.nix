# nix/build/compile-db.nix
#
# compile_commands.json for every C component, from a release build run under bear.
# The C analysis tools need the configured tree as well (config.h, generated
# headers), so each output keeps it:
#
#   $out/<name>/tree/                  the component after configure + make
#   $out/<name>/compile_commands.json  paths written as @ROOT@/<name>/...
#
# passthru.setup is a shell snippet that copies every component into ./src and
# writes ./compile_commands.json for that copy, so a tool can run anywhere.  The
# /nix/store include paths in the DB keep the headers in this output's closure.

{ pkgs, lib, cPkgs }:

let
  one = name: cPkgs.buildC "release" name {
    pname = "infix-compile-db-${name}";
    nativeBuildInputs = (cPkgs.buildC "release" name { }).nativeBuildInputs ++ [ pkgs.bear pkgs.jq ];
    buildPhase = ''
      runHook preBuild
      bear --output compile_commands.json -- make -j$NIX_BUILD_CORES "''${makeFlagsArray[@]}" $makeFlags
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out/${name}"
      root=$(dirname "$PWD")
      # The cc-wrapper adds NIX_CFLAGS_COMPILE (the -isystem paths of every
      # dependency, extra defines) where bear cannot see it; put it in each entry.
      jq --arg extra "$NIX_CFLAGS_COMPILE" '
        ($extra | split(" ") | map(select(length > 0))) as $x
        | map(.arguments = [.arguments[0]] + $x + .arguments[1:])' compile_commands.json \
        | sed "s|$root|@ROOT@|g" > "$out/${name}/compile_commands.json"
      n=$(jq length "$out/${name}/compile_commands.json")
      echo "${name}: $n compile commands"
      [ "$n" -gt 0 ] || { echo "bear recorded nothing for ${name}"; exit 1; }
      rm compile_commands.json
      cp -r . "$out/${name}/tree"
    '';
    dontFixup = true;
  };

  perComponent = lib.genAttrs cPkgs.names one;
  db = pkgs.symlinkJoin {
    name = "infix-compile-db";
    paths = lib.attrValues perComponent;
    passthru = {
      inherit perComponent;
      setup = ''
        mkdir -p src
        for c in ${toString cPkgs.names}; do
          cp -rL --no-preserve=mode ${db}/$c/tree src/$c
          sed "s|@ROOT@|$PWD/src|g" ${db}/$c/compile_commands.json > src/$c.json
        done
        ${pkgs.jq}/bin/jq -s 'add | unique_by([.directory, .file])' src/*.json > compile_commands.json
        rm src/*.json
      '';
    };
  };
in
db
