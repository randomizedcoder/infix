"""The Finding record, and path and severity normalization."""

import re
from dataclasses import dataclass, field

_STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[^/]*/")
_BUILD = re.compile(r"^(/build|/tmp/nix-build-[^/]+)/(work/|source/)?")


@dataclass
class Finding:
    tool: str
    check_id: str
    severity: str  # error, warning, style
    file: str      # relative to the repository root
    line: int
    message: str
    category: str = ""
    score: float = 0.0
    tools: list = field(default_factory=list)

    def dedup_key(self):
        return (self.file, self.line, self.check_id)


def normalize_path(path):
    """Strip store and sandbox prefixes and ./, and collapse //."""
    path = _STORE.sub("", path.strip())
    path = _BUILD.sub("", path)
    while "//" in path:
        path = path.replace("//", "/")
    path = path.removeprefix("./")
    return path


def normalize_severity(sev):
    """Map each tool's severity words onto error, warning or style."""
    sev = sev.lower().strip()
    if sev in ("error", "high", "critical", "5", "4"):
        return "error"
    if sev in ("style", "low", "info", "information", "note", "1", "0", "unspecified"):
        return "style"
    return "warning"
