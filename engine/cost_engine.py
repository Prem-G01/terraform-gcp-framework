"""Static cost-threshold check.

This is deliberately NOT a Cloud Billing API integration — see
config/global/cost.yaml for why, and docs/validation.md for what a real
integration would require. It estimates monthly spend from a static
USD/hour table for the resource types that dominate a small platform's bill
(VMs, Cloud SQL) and warns — never blocks — if the estimate crosses a
configurable per-environment threshold.
"""

from __future__ import annotations

from pathlib import Path

import yaml

from engine.errors import Finding

HOURS_PER_MONTH = 730


def load_cost_config(config_root: Path) -> dict:
    path = Path(config_root) / "global" / "cost.yaml"
    if not path.is_file():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def validate_cost(deployment, config_root: Path) -> list[Finding]:
    cost_config = load_cost_config(config_root)
    if not cost_config:
        return []

    vm_rates = cost_config.get("machine_type_hourly_usd", {})
    sql_rates = cost_config.get("cloudsql_tier_hourly_usd", {})
    threshold = cost_config.get("thresholds", {}).get("monthly_usd_warning", {}).get(deployment.environment)

    estimated = 0.0
    unknown_types: list[str] = []

    if "vm" in deployment.enabled_resource_types():
        for name, vm in deployment.instances("vm").items():
            machine_type = vm.get("machine_type")
            rate = vm_rates.get(machine_type)
            if rate is None:
                unknown_types.append(f"vm.{name} ({machine_type})")
                continue
            estimated += rate * HOURS_PER_MONTH

    if "cloudsql" in deployment.enabled_resource_types():
        for name, sql in deployment.instances("cloudsql").items():
            tier = sql.get("tier")
            rate = sql_rates.get(tier)
            if rate is None:
                unknown_types.append(f"cloudsql.{name} ({tier})")
                continue
            estimated += rate * HOURS_PER_MONTH

    findings: list[Finding] = []
    if unknown_types:
        findings.append(
            Finding(
                severity="WARNING",
                category="cost",
                rule="COST_ESTIMATE_INCOMPLETE",
                resource="deployment",
                message=(
                    "No static rate in config/global/cost.yaml for: " + ", ".join(unknown_types) +
                    ". Estimate below excludes them."
                ),
            )
        )

    if threshold is not None and estimated > threshold:
        findings.append(
            Finding(
                severity="WARNING",
                category="cost",
                rule="COST_THRESHOLD_EXCEEDED",
                resource="deployment",
                message=(
                    f"Estimated compute+Cloud SQL spend ~${estimated:,.2f}/mo exceeds the "
                    f"{deployment.environment} warning threshold of ${threshold:,.2f}/mo "
                    "(static list-price estimate, not live billing — see config/global/cost.yaml)."
                ),
            )
        )

    return findings
