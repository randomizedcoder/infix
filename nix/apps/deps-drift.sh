# deps-drift <infix-root> <buildroot-dir> <pins-file>
#
# Each pins-file line is "<base> <file> <VARIABLE> <pinned-value>", where base is
# infix or buildroot.  Fails when a .mk file sets the variable to another value,
# and warns about patches/<pkg>/<version>/ directories for versions not pinned.
root=$1
br=$2
pins=$3
drift=0
while read -r base file var want; do
  case $base in
    infix) path=$root/$file ;;
    buildroot) path=$br/$file ;;
    *) continue ;;
  esac
  if [ ! -f "$path" ]; then
    echo "MISSING  $base/$file"
    drift=$((drift + 1))
    continue
  fi
  have=$(sed -nE "s/^${var}[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$path" | head -n 1)
  if [ "$have" = "$want" ]; then
    echo "ok       $var = $want"
  else
    echo "DRIFT    $var: $base/$file has '$have', nix/deps/pins.nix has '$want'"
    drift=$((drift + 1))
  fi
  pkg=$(basename "$file" .mk)
  for d in "$root/patches/$pkg"/*/; do
    [ -d "$d" ] || continue
    v=$(basename "$d")
    if [ "$v" != "$want" ]; then
      echo "warning  patches/$pkg/$v/ is for $v, but $pkg is at $want (stale?)"
    fi
  done
done < "$pins"
if [ -n "${BUILDROOT_REV:-}" ] && git -C "$root" rev-parse -q --verify HEAD:buildroot >/dev/null 2>&1; then
  sub=$(git -C "$root" rev-parse HEAD:buildroot)
  if [ "$sub" = "$BUILDROOT_REV" ]; then
    echo "ok       buildroot submodule = flake input ($sub)"
  else
    echo "DRIFT    buildroot submodule is $sub, the flake's buildroot input is $BUILDROOT_REV"
    drift=$((drift + 1))
  fi
fi
echo "$drift drifted pin(s)"
[ "$drift" -eq 0 ]
