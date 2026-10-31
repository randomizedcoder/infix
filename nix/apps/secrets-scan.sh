# secrets-scan [outdir]: gitleaks over the whole git history.
out=${1:-secrets-scan-out}
mkdir -p "$out"
if gitleaks git --redact --no-banner --report-format json --report-path "$out/gitleaks.json" .; then
  echo "No secrets found."
else
  rc=$?
  jq -r '.[] | "\(.File):\(.StartLine): \(.RuleID) (commit \(.Commit[0:12]))"' "$out/gitleaks.json" \
    | tee "$out/report.txt"
  exit "$rc"
fi
