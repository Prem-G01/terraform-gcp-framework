"""Region/zone allow-list validation — config/global/regions.yaml."""

from __future__ import annotations

from engine.errors import Finding

_REGION_FIELDS = ("region", "location")
_ZONE_FIELDS = ("zone",)


def _region_of_zone(zone: str) -> str:
    parts = zone.rsplit("-", 1)
    return parts[0] if len(parts) == 2 else zone


def validate_regions(deployment) -> list[Finding]:
    approved = {r.lower() for r in deployment.global_config.regions.get("regions", {}).get("approved", [])}
    multi_region = {r.lower() for r in deployment.global_config.regions.get("regions", {}).get("multi_region_locations", [])}
    allowed_locations = approved | multi_region | {"global", "us", "eu", "asia"}
    findings: list[Finding] = []

    primary = deployment.raw.get("region", {}).get("primary")
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
                if value.lower() in allowed_locations or _region_of_zone(value).lower() in approved:
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
                if value and _region_of_zone(value).lower() not in approved:
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
