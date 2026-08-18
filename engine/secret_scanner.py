"""Secret scanner.

Scans the whole repository (not just modules/platform/bootstrap — a leaked
secret can land anywhere, including docs or a config file) for content
that looks like an actual credential VALUE, not a credential NAME.

Deliberately high-confidence patterns only. This repo has many
legitimately-named fields — `password_secret:`, `secret_id:`,
`existing_access_policy_id:` — that reference or describe a secret without
containing one; a generic "looks secret-ish" heuristic would drown in
false positives on exactly those fields. What's checked instead:

  - PEM private key blocks (RSA/EC/DSA/OpenSSH/generic) — essentially
    zero false-positive rate.
  - A GCP service-account JSON key's structural signature (`"type":
    "service_account"` plus `"private_key"` in the same file) — real key
    files, not just a field named private_key.
  - AWS access key IDs (`AKIA[0-9A-Z]{16}`) — a fixed, recognizable format.
  - Slack tokens (`xox[baprs]-...`) — another fixed, recognizable format.

A line can suppress a finding with a trailing `# secret-allow: <reason>`
comment, same convention as engine/hardcode_scanner.py.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

ALLOW_MARKER = "secret-allow"

# Directories never worth scanning — generated/vendored/cache content.
_SKIP_DIR_NAMES = {".git", ".terraform", "__pycache__", ".pytest_cache", "archive", "node_modules"}

_PEM_HEADER = re.compile(r"-----BEGIN ([A-Z ]*PRIVATE KEY)-----")
_AWS_ACCESS_KEY = re.compile(r"\bAKIA[0-9A-Z]{16}\b")
_SLACK_TOKEN = re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b")
# Requires the PEM header inside the JSON value itself — a real GCP
# service-account key file always has this exact shape. Matching on the
# field name alone (`"private_key":`) would also flag this scanner's own
# source code, which mentions that field name in its pattern definitions
# and docstring without containing an actual key.
_GCP_SA_KEY_VALUE = re.compile(r'"private_key"\s*:\s*"-----BEGIN')


@dataclass
class SecretFinding:
    file: str
    line: int
    rule: str
    severity: str = "ERROR"
    recommendation: str = "Revoke this credential immediately (assume it's compromised the moment it's committed), then remove it from the file and from git history."

    def render(self) -> str:
        return (
            "SECRET SCAN FINDING\n\n"
            f"File:\n  {self.file}\n\n"
            f"Line:\n  {self.line}\n\n"
            f"Rule:\n  {self.rule}\n\n"
            f"Severity:\n  {self.severity}\n\n"
            f"Recommendation:\n  {self.recommendation}"
        )


def _iter_target_files(repo_root: Path):
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in _SKIP_DIR_NAMES for part in path.parts):
            continue
        yield path


def _is_text_file(path: Path) -> bool:
    try:
        path.read_text(encoding="utf-8")
        return True
    except (UnicodeDecodeError, PermissionError, OSError):
        return False


def scan(repo_root: Path) -> list[SecretFinding]:
    repo_root = Path(repo_root)
    findings: list[SecretFinding] = []

    for file_path in _iter_target_files(repo_root):
        if not _is_text_file(file_path):
            continue
        text = file_path.read_text(encoding="utf-8")
        rel = str(file_path.relative_to(repo_root)).replace("\\", "/")

        for i, line in enumerate(text.splitlines(), start=1):
            if ALLOW_MARKER in line:
                continue

            if _PEM_HEADER.search(line):
                findings.append(SecretFinding(file=rel, line=i, rule="PEM_PRIVATE_KEY"))
            if _AWS_ACCESS_KEY.search(line):
                findings.append(SecretFinding(file=rel, line=i, rule="AWS_ACCESS_KEY_ID"))
            if _SLACK_TOKEN.search(line):
                findings.append(SecretFinding(file=rel, line=i, rule="SLACK_TOKEN"))
            if _GCP_SA_KEY_VALUE.search(line):
                findings.append(SecretFinding(file=rel, line=i, rule="GCP_SERVICE_ACCOUNT_KEY_FILE"))

    return findings
