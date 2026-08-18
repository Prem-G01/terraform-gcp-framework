"""Hard-code scanner.

Scans Terraform (and this engine's own Python) for values that should have
come from configuration instead of being baked into reusable code:
project ids, regions/zones, CIDR ranges, service-account emails, and a bare
environment-name literal.

Deliberately scoped to modules/, platform/, and bootstrap/ (the reusable,
environment-agnostic layers) plus environments/**/main.tf and provider.tf —
NOT config/**/*.yaml (real values belong there by design) and NOT
environments/**/*.tfvars* or backend.tf (those are the one sanctioned place
per-environment identity is set, see docs/configuration.md).

A line can suppress a finding with a trailing `# hardcode-allow: <reason>`
comment — use it sparingly, and only for values that really are constants
(e.g. a fixed IANA port number), not to silence real hardcoding.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

SCAN_DIRS = ("modules", "platform", "bootstrap")
SCAN_EXTRA_FILES = ("main.tf", "provider.tf", "locals.tf")  # inside environments/*/

ALLOW_MARKER = "hardcode-allow"

# Legitimate GCP API enum / constant strings that happen to look suspicious
# but are not environment-specific — never flagged.
_SAFE_LITERALS = re.compile(
    r"^(GLOBAL|PRIVATE|ACTIVE|REGIONAL|AUTO_ONLY|ALL_SUBNETWORKS_ALL_IP_RANGES|"
    r"ENCRYPT_DECRYPT|STANDARD|ZONAL|DEFAULT|INGRESS|EGRESS|HTTP|HTTPS|POST|GET|"
    r"INTERNAL|VPC_PEERING|SERVERLESS)$"
)

_DETECTORS = [
    ("PROJECT_ID_LITERAL", re.compile(r'"(prj-[a-z0-9-]{4,28}|[a-z][a-z0-9-]{4,28}-(dev|sit|uat|prod))"')),
    ("REGION_OR_ZONE_LITERAL", re.compile(
        r'"((asia|us|europe|australia|northamerica|southamerica|me|africa)-[a-z]+\d(-[a-z])?)"'
    )),
    ("CIDR_LITERAL", re.compile(r'"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2})"')),
    ("SERVICE_ACCOUNT_EMAIL_LITERAL", re.compile(r'"([\w.-]+@[\w.-]+\.iam\.gserviceaccount\.com)"')),
    ("ENVIRONMENT_NAME_LITERAL", re.compile(r'\benvironment\s*=\s*"(dev|sit|uat|prod)"')),
]


@dataclass
class HardcodeFinding:
    file: str
    line: int
    rule: str
    value: str
    severity: str = "ERROR"
    recommendation: str = "Move this value into config/environments/<env>/deployment.yaml or config/global/."

    def render(self) -> str:
        return (
            "HARDCODE ANALYSIS\n\n"
            f"File:\n  {self.file}\n\n"
            f"Line:\n  {self.line}\n\n"
            f"Detected:\n  {self.value}\n\n"
            f"Rule:\n  {self.rule}\n\n"
            f"Severity:\n  {self.severity}\n\n"
            f"Recommendation:\n  {self.recommendation}"
        )


def _iter_target_files(repo_root: Path):
    for dirname in SCAN_DIRS:
        base = repo_root / dirname
        if base.is_dir():
            yield from base.rglob("*.tf")
    env_root = repo_root / "environments"
    if env_root.is_dir():
        for env_dir in env_root.iterdir():
            for fname in SCAN_EXTRA_FILES:
                candidate = env_dir / fname
                if candidate.is_file():
                    yield candidate


def scan(repo_root: Path) -> list[HardcodeFinding]:
    repo_root = Path(repo_root)
    findings: list[HardcodeFinding] = []

    for file_path in _iter_target_files(repo_root):
        try:
            lines = file_path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for i, line in enumerate(lines, start=1):
            if ALLOW_MARKER in line:
                continue
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            for rule, regex in _DETECTORS:
                for match in regex.finditer(line):
                    value = match.group(1)
                    if _SAFE_LITERALS.match(value):
                        continue
                    findings.append(
                        HardcodeFinding(
                            file=str(file_path.relative_to(repo_root)).replace("\\", "/"),
                            line=i,
                            rule=rule,
                            value=value,
                        )
                    )
    return findings
