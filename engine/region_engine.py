"""Region/zone allow-list validation — config/global/regions.yaml."""

from __future__ import annotations

from engine.errors import Finding

_REGION_FIELDS = ("region", "location")
_ZONE_FIELDS = ("zone",)


def _region_of_zone(zone: str) -> str:
    parts = zone.rsplit("-", 1)
    return parts[0] if len(parts) == 2 else zone


def _suffix_of_zone(zone: str) -> str | None:
    parts = zone.rsplit("-", 1)
    return parts[1] if len(parts) == 2 else None


def validate_regions(deployment) -> list[Finding]:
    approved = {r.lower() for r in deployment.global_config.regions.get("regions", {}).get("approved", [])}
    multi_region = {r.lower() for r in deployment.global_config.regions.get("regions", {}).get("multi_region_locations", [])}
    zone_suffixes = {s.lower() for s in deployment.global_config.regions.get("regions", {}).get("zone_suffixes", [])}
    allowed_locations = approved | multi_region | {"global", "us", "eu", "asia"}

    def _is_approved_zone(value: str) -> bool:
        # config/global/regions.yaml's zone_suffixes was defined but never
        # actually read anywhere — a zone's region prefix being approved
        # was the only check ever applied, so e.g. "asia-south1-z" passed
        # validation even though "z" was never an approved suffix. Found
        # 2026-08-24 (same class of gap as security_defaults.yaml, see
        # docs/security.md).
        suffix = _suffix_of_zone(value)
        return _region_of_zone(value).lower() in approved and suffix is not None and suffix.lower() in zone_suffixes

    findings: list[Finding] = []

    primary = deployment.region
    if primary and primary.lower() not in approved:
        findings.append(
            Finding(
                severity="ERROR",
                category="region",
                rule="REGION_NOT_APPROVED",
                resource="region.primary",
                message=f"'{primary}' is not in config/global/regions.yaml regions.approved ({sorted(approved)}).",
            )
        )

    for rtype in deployment.enabled_resource_types():
        for name, instance in deployment.instances(rtype).items():
            if not isinstance(instance, dict):
                continue
            for field in _REGION_FIELDS:
                value = instance.get(field)
                if not value:
                    continue
                # `location` in particular can be a bare region (most
                # resource types) OR a zone (GKE supports zonal clusters,
                # e.g. "asia-south1-a") — accept either shape, but a zone
                # still has to sit inside an approved region.
                if value.lower() in allowed_locations or _is_approved_zone(value):
                    continue
                findings.append(
                    Finding(
                        severity="ERROR",
                        category="region",
                        rule="REGION_NOT_APPROVED",
                        resource=f"{rtype}.{name}",
                        message=f"{field} = '{value}' is not an approved region/location.",
                    )
                )
            for field in _ZONE_FIELDS:
                value = instance.get(field)
                if value and not _is_approved_zone(value):
                    findings.append(
                        Finding(
                            severity="ERROR",
                            category="region",
                            rule="ZONE_NOT_APPROVED",
                            resource=f"{rtype}.{name}",
                            message=f"{field} = '{value}' is not in an approved region.",
                        )
                    )
    return findings
