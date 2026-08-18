"""Command-line entrypoint for the validation engine.

    python -m engine.cli validate config/environments/dev
    python -m engine.cli validate config/environments/dev --json
    python -m engine.cli hardcode-scan .
    python -m engine.cli validate-all config

Exit code is 0 when nothing blocks the deployment (no ERROR-severity
findings), 1 otherwise — this is the gate CI/CD checks (see cicd/cloudbuild.yaml
"Validation" step and docs/cicd.md).
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from engine import config_loader, cost_engine, dependency_engine, naming_engine, region_engine, schema_validator, security_engine
from engine.errors import ValidationReport


def run_validation(env_dir: Path) -> ValidationReport:
    report = ValidationReport()
    env_dir = Path(env_dir)
    config_root = env_dir.parent.parent

    try:
        deployment = config_loader.load_deployment(env_dir, config_root)
    except config_loader.ConfigError as exc:
        from engine.errors import Finding
        report.add(Finding(severity="ERROR", category="yaml", rule="YAML_SYNTAX_ERROR", resource=str(env_dir), message=str(exc)))
        return report

    report.extend(schema_validator.validate_schema(deployment.raw, config_root))
    if report.blocked:
        # A malformed envelope makes every downstream check meaningless / crash-prone.
        return report

    report.extend(schema_validator.validate_required_fields(deployment))
    report.extend(dependency_engine.validate_dependency_graph_integrity(deployment.global_config))
    report.extend(dependency_engine.validate_type_dependencies(deployment))
    report.extend(dependency_engine.validate_instance_references(deployment))
    report.extend(security_engine.validate_security(deployment))
    report.extend(naming_engine.validate_naming(deployment))
    report.extend(region_engine.validate_regions(deployment))
    report.extend(cost_engine.validate_cost(deployment, config_root))
    return report


def cmd_validate(args: argparse.Namespace) -> int:
    report = run_validation(Path(args.env_dir))
    if args.json:
        payload = {
            "blocked": report.blocked,
            "errors": len(report.errors),
            "warnings": len(report.warnings),
            "findings": [
                {
                    "severity": f.severity,
                    "category": f.category,
                    "rule": f.rule,
                    "resource": f.resource,
                    "message": f.message,
                    "missing": f.missing,
                }
                for f in report.findings
            ],
        }
        print(json.dumps(payload, indent=2))
    else:
        print(report.render())
    return 1 if report.blocked else 0


def cmd_validate_all(args: argparse.Namespace) -> int:
    config_root = Path(args.config_root)
    envs = config_loader.discover_environments(config_root)
    if not envs:
        print(f"No environments found under {config_root}/environments/")
        return 1
    worst = 0
    for env_dir in envs:
        print(f"\n=== {env_dir.name} ===")
        rc = cmd_validate(argparse.Namespace(env_dir=env_dir, json=False))
        worst = max(worst, rc)
    return worst


def cmd_render(args: argparse.Namespace) -> int:
    """Validate, then — only if nothing blocks — write the normalized
    deployment as JSON for Terraform to consume. This is the mechanical
    enforcement of "don't let Terraform run against an invalid config":
    platform/variables.tf's deployment_file points at this file, and if
    render refuses to write it, `terraform plan` fails on a missing file
    rather than silently applying something nobody validated.

    --force-security is the one sanctioned break-glass path: it downgrades
    SECURITY-category ERROR findings only (e.g. temporarily disabling
    deletion_protection to tear a resource down — see docs/troubleshooting.md
    "Dev was applied, then torn down"). Schema/dependency/YAML/naming/region
    errors are never forceable — those mean the config itself is broken,
    not that a deliberate policy exception is being made. Every use is
    written to an audit trail next to the rendered output; nothing about
    this is silent."""
    env_dir = Path(args.env_dir)
    report = run_validation(env_dir)

    if report.blocked and args.force_security:
        non_security_errors = [f for f in report.errors if f.category != "security"]
        if non_security_errors:
            print(report.render())
            print(
                "\n--force-security cannot help here — the block includes "
                f"{len(non_security_errors)} non-security error(s) "
                "(schema/dependency/naming/region/yaml). Fix those first."
            )
            return 1
        forced = [f for f in report.errors if f.category == "security"]
    elif report.blocked:
        print(report.render())
        print("\nRefusing to render — fix the error(s) above before running terraform.")
        return 1
    else:
        forced = []

    deployment = config_loader.load_deployment(env_dir, env_dir.parent.parent)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(deployment.normalized, indent=2), encoding="utf-8")

    if forced:
        banner = "!" * 78
        print(banner)
        print("SECURITY OVERRIDE IN EFFECT — the following ERROR-severity findings")
        print("were forced through and did NOT block this render:")
        print(banner)
        for f in forced:
            print(f"  [{f.rule}] {f.resource}: {f.message}")
        print(f"Reason given: {args.reason}")
        print(banner)
        _write_override_audit(out_path, env_dir, args.reason, forced)
    elif report.warnings:
        print(report.render())
        print()

    print(f"Wrote validated, normalized config to {out_path}")
    return 0


def _write_override_audit(out_path: Path, env_dir: Path, reason: str, forced) -> None:
    audit_path = out_path.parent / "override-audit.jsonl"
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "environment": str(env_dir),
        "user": os.environ.get("USER") or os.environ.get("USERNAME") or getpass.getuser(),
        "reason": reason,
        "overridden_findings": [
            {"rule": f.rule, "resource": f.resource, "message": f.message} for f in forced
        ],
    }
    with audit_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record) + "\n")
    print(f"Audit record appended to {audit_path}")


def cmd_hardcode_scan(args: argparse.Namespace) -> int:
    from engine import hardcode_scanner

    findings = hardcode_scanner.scan(Path(args.repo_root))
    if not findings:
        print("HARDCODE SCAN: no suspicious literals found in modules/, platform/, bootstrap/, environments/*/main.tf")
        return 0
    for f in findings:
        print(f.render())
        print()
    print(f"{len(findings)} suspected hardcoded value(s) found.")
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="platform-cli")
    sub = parser.add_subparsers(dest="command", required=True)

    p_validate = sub.add_parser("validate", help="Validate one environment's deployment.yaml")
    p_validate.add_argument("env_dir", help="e.g. config/environments/dev")
    p_validate.add_argument("--json", action="store_true")
    p_validate.set_defaults(func=cmd_validate)

    p_validate_all = sub.add_parser("validate-all", help="Validate every environment under config/environments/")
    p_validate_all.add_argument("config_root", nargs="?", default="config")
    p_validate_all.set_defaults(func=cmd_validate_all)

    p_render = sub.add_parser("render", help="Validate + write the normalized deployment JSON Terraform consumes")
    p_render.add_argument("env_dir", help="e.g. config/environments/dev")
    p_render.add_argument("--out", required=True, help="e.g. environments/dev/.generated/deployment.normalized.json")
    p_render.add_argument(
        "--force-security",
        action="store_true",
        help="Break-glass: forces through SECURITY-category ERROR findings only (never schema/dependency/naming/region/yaml). Requires --reason. Audited — see docs/validation.md.",
    )
    p_render.add_argument("--reason", help="Required with --force-security: why this override is deliberate and safe.")
    p_render.set_defaults(func=cmd_render)

    p_scan = sub.add_parser("hardcode-scan", help="Scan modules/platform/bootstrap for hardcoded values")
    p_scan.add_argument("repo_root", nargs="?", default=".")
    p_scan.set_defaults(func=cmd_hardcode_scan)

    args = parser.parse_args(argv)
    if args.command == "render" and args.force_security and not args.reason:
        parser.error("--force-security requires --reason \"<why this is deliberate and safe>\"")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
