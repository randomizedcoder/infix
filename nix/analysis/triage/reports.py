"""Write findings.json, triage.md, top.txt and count.txt."""

import json
from collections import Counter
from dataclasses import asdict
from pathlib import Path


def write_all(findings, out_dir, top=60):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "findings.json").write_text(json.dumps([asdict(f) for f in findings], indent=1))
    (out / "count.txt").write_text(f"{len(findings)}\n")

    lines = [f"{f.score:6.1f}  {f.category:<14} {f.file}:{f.line}  {f.check_id}  ({','.join(f.tools)})  {f.message}"
             for f in findings[:top]]
    (out / "top.txt").write_text("\n".join(lines) + "\n")

    by_cat = Counter(f.category for f in findings)
    by_tool = Counter(f.tool for f in findings)
    md = ["# Triage", "",
          f"{len(findings)} findings after filtering and deduplication.", "",
          "| Category | Findings |", "|---|---:|"]
    md += [f"| {c} | {n} |" for c, n in by_cat.most_common()]
    md += ["", "| Tool | Findings |", "|---|---:|"]
    md += [f"| {t} | {n} |" for t, n in by_tool.most_common()]
    md += ["", f"## Top {min(top, len(findings))}", "",
           "| Score | Class | Location | Check | Tools | Message |", "|---:|---|---|---|---|---|"]
    md += [f"| {f.score} | {f.category} | `{f.file}:{f.line}` | {f.check_id} | {', '.join(f.tools)} "
           f"| {f.message.replace('|', '/')[:160]} |" for f in findings[:top]]
    (out / "triage.md").write_text("\n".join(md) + "\n")
