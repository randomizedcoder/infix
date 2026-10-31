"""One parser per report format; load() reads every tool under a tier directory.

Each tool writes <tier>/<tool>/report.txt.  Most use the compiler format
"file:line:col: severity: message [check]"; the rest have a parser here.
"""

import re
from pathlib import Path

from finding import Finding, normalize_path, normalize_severity

# file:line:col: severity: message [check]
_GCC = re.compile(r"^([^:\s]+):(\d+):(\d+): (\w+): (.*?)(?: \[([^\]]+)\])?$")
# ruff concise: file:line:col: CODE message
_RUFF = re.compile(r"^([^:\s]+):(\d+):(\d+): ([A-Z]+[0-9]+) (?:\[\*\] )?(.*)$")
# flawfinder --singleline: file:line:col:  [level] (category) function:message
_FLAW = re.compile(r"^([^:\s]+):(\d+):(\d+): +\[(\d)\] \((\w+)\) (\w+):(.*)$")
# bandit custom template: file:line: SEVERITY: test_id: message
_BANDIT = re.compile(r"^([^:\s]+):(\d+): (LOW|MEDIUM|HIGH): (B\d+): (.*)$")
# golangci-lint / go vet: file:line[:col]: message (linter)
_GO = re.compile(r"^([^:\s]+\.go):(\d+)(?::(\d+))?: (.*?)(?: \((\w+)\))?$")
# gosec, after gosec.nix's sed: file:line: G204 (CWE-78): message
_GOSEC = re.compile(r"^([^:\s]+):(\d+):\d+: (\w+): (G\d+): (.*)$")
# CodeChecker parse: [SEVERITY] file:line:col: message [checker]
_CC = re.compile(r"^\[(\w+)\] ([^:\s]+):(\d+):(\d+): (.*?) \[([^\]]+)\]$")


def parse_gcc(text, tool):
    out = []
    for line in text.splitlines():
        m = _GCC.match(line)
        if m and m.group(4) in ("error", "warning", "note", "style", "performance",
                                "portability", "information", "info"):
            out.append(Finding(tool, m.group(6) or m.group(4), normalize_severity(m.group(4)),
                               normalize_path(m.group(1)), int(m.group(2)), m.group(5)))
    return out


def parse_ruff(text, tool):
    out = []
    for line in text.splitlines():
        m = _RUFF.match(line)
        if m:
            code = m.group(4)
            sev = "error" if code.startswith(("F8", "E9", "PLE")) else "warning"
            out.append(Finding(tool, code, sev, normalize_path(m.group(1)), int(m.group(2)), m.group(5)))
    return out


def parse_flawfinder(text, tool):
    out = []
    for line in text.splitlines():
        m = _FLAW.match(line)
        if m:
            level = int(m.group(4))
            sev = "error" if level >= 4 else "warning" if level >= 2 else "style"
            out.append(Finding(tool, f"{m.group(5)}.{m.group(6)}", sev, normalize_path(m.group(1)),
                               int(m.group(2)), m.group(7).strip()))
    return out


def parse_bandit(text, tool):
    out = []
    for line in text.splitlines():
        m = _BANDIT.match(line)
        if m:
            out.append(Finding(tool, m.group(4), normalize_severity(m.group(3)),
                               normalize_path(m.group(1)), int(m.group(2)), m.group(5)))
    return out


def parse_go(text, tool):
    out = []
    for line in text.splitlines():
        m = _GO.match(line)
        if m:
            check, msg = m.group(5) or "vet", m.group(4)
            # gosec through golangci-lint: "G204: message"; keep gosec's rule id.
            rule = re.match(r"(G\d+): (.*)", msg) if check == "gosec" else None
            if rule:
                check, msg = rule.groups()
            out.append(Finding(tool, check, "warning", normalize_path(m.group(1)), int(m.group(2)), msg))
    return out


def parse_gosec(text, tool):
    out = []
    for line in text.splitlines():
        m = _GOSEC.match(line)
        if m:
            out.append(Finding(tool, m.group(4), normalize_severity(m.group(3)),
                               normalize_path(m.group(1)), int(m.group(2)), m.group(5)))
    return out


def parse_codechecker(text, tool):
    out = []
    for line in text.splitlines():
        m = _CC.match(line)
        if m:
            out.append(Finding(tool, m.group(6), normalize_severity(m.group(1)),
                               normalize_path(m.group(2)), int(m.group(3)), m.group(5)))
    return out


PARSERS = {
    "clang-format": parse_gcc,
    "shellcheck": parse_gcc,
    "cppcheck": parse_gcc,
    "cppcheck-exhaustive": parse_gcc,
    "clang-tidy": parse_gcc,
    "gcc-analyzer": parse_gcc,
    "semgrep": parse_gcc,
    "ruff": parse_ruff,
    "flawfinder": parse_flawfinder,
    "bandit": parse_bandit,
    "go-vet": parse_go,
    "golangci-lint": parse_go,
    "golangci-lint-comprehensive": parse_go,
    "gosec": parse_gosec,
    "codechecker": parse_codechecker,
    # The fuzz runs: one line per distinct crash, in the gcc format.
    "fuzz": parse_gcc,
    "go-fuzz": parse_gcc,
}


def parse(tool, text):
    """Findings from one tool's report text; [] for a tool without a parser."""
    fn = PARSERS.get(tool)
    return fn(text, tool) if fn else []


def load(result_dir):
    """Every finding under result_dir/<tool>/report.txt."""
    findings = []
    for report in sorted(Path(result_dir).glob("*/report.txt")):
        findings.extend(parse(report.parent.name, report.read_text(errors="replace")))
    return findings
