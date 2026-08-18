"""Shared error/result types for the validation engine.

Every check in engine/*.py returns a list of Finding objects instead of
raising, so the CLI can run every category and report everything wrong in
one pass instead of stopping at the first error (see engine/cli.py).
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Finding:
    severity: str          # "ERROR" or "WARNING"
    category: str          # "yaml" | "schema" | "dependency" | "security" | "naming" | "region" | "hardcode"
    rule: str               # stable rule id, e.g. "VM_NETWORK_REQUIRED"
    resource: str            # e.g. "vm.app01" or "<file>:<line>"
    message: str
    missing: list[str] = field(default_factory=list)

    def render(self) -> str:
        lines = [
            "VALIDATION FAILED" if self.severity == "ERROR" else "VALIDATION WARNING",
            "",
            "Resource:",
            f"  {self.resource}",
            "",
            "Rule:",
            f"  {self.rule}",
            "",
            "Error:" if self.severity == "ERROR" else "Warning:",
            f"  {self.message}",
        ]
        if self.missing:
            lines += ["", "Missing:"] + [f"  {m}" for m in self.missing]
        return "\n".join(lines)


class ValidationReport:
    """Aggregates findings from every engine and renders a final verdict."""

    def __init__(self) -> None:
        self.findings: list[Finding] = []

    def add(self, finding: Finding) -> None:
        self.findings.append(finding)

    def extend(self, findings: list[Finding]) -> None:
        self.findings.extend(findings)

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "ERROR"]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "WARNING"]

    @property
    def blocked(self) -> bool:
        return len(self.errors) > 0

    def render(self) -> str:
        if not self.findings:
            return "VALIDATION PASSED\n\nNo errors or warnings. Deployment allowed."

        parts = [f.render() for f in self.findings]
        summary = (
            f"\n{'=' * 60}\n"
            f"{len(self.errors)} error(s), {len(self.warnings)} warning(s).\n"
            + ("Deployment blocked." if self.blocked else "Deployment allowed (warnings only).")
        )
        return ("\n\n" + "-" * 60 + "\n\n").join(parts) + summary
