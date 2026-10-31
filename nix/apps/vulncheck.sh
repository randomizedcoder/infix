# vulncheck [outdir]: govulncheck over each Go module and osv-scanner over the
# tree's lock files, against the online vulnerability databases.  The image is
# built with Buildroot's Go, so govulncheck checks the standard library at that
# version rather than at the version in this shell.
out=${1:-vulncheck-out}
mkdir -p "$out"
rc=0
mk=buildroot/package/go/go.mk
if [ -f "$mk" ]; then
  GOVERSION=go$(sed -nE 's/^GO_VERSION = (.*)/\1/p' "$mk")
  export GOVERSION
  echo "Standard library: $GOVERSION (from $mk)"
fi
for m in $GO_MODULES; do
  echo "== govulncheck src/$m"
  if (cd "src/$m" && govulncheck ./...) > "$out/govulncheck-$m.txt" 2>&1; then
    echo "   no reachable vulnerabilities"
  else
    rc=1
    grep -E '^Vulnerability #|Found in|Fixed in' "$out/govulncheck-$m.txt" | sed 's/^/   /' || true
  fi
done
echo "== osv-scanner"
if osv-scanner scan source --recursive --format table . > "$out/osv-scanner.txt" 2>&1; then
  echo "   no known vulnerabilities"
else
  rc=1
  tail -n 30 "$out/osv-scanner.txt"
fi
echo "Reports in $out/"
exit "$rc"
