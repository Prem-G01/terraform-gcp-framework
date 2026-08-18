"""Naming validation — config/global/naming.yaml against project id,
environment, and resource instance keys (the instance key becomes the GCP
resource name unless an instance explicitly overrides it, see modules/*
`lookup(each.value, "name", each.key)`)."""

from __future__ import annotations

import re

from engine.errors import Finding

_ALLOWED_ENVIRONMENTS = {"dev", "sit", "uat", "prod"}


def validate_naming(deployment) -> list[Finding]:
    naming = deployment.global_config.naming.get("naming", {})
    max_len = naming.get("max_length", {})
    allowed_chars = naming.get("allowed_characters", {})
    default_pattern = allowed_chars.get("default", "^[a-z][a-z0-9-]*[a-z0-9]$")
    # Resource types whose GCP naming rules genuinely differ from the
    # default compute-style pattern (e.g. BigQuery datasets allow
    # underscores and mixed case; buckets allow dots).
    TYPE_PATTERN_KEY = {"bigquery": "bigquery_dataset", "buckets": "bucket"}
    findings: list[Finding] = []

    project_id = deployment.raw.get("project", {}).get("id", "")
    project_max = max_len.get("project_id", 30)
    if len(project_id) > project_max:
        findings.append(
            Finding(
                severity="ERROR",
                category="naming",
                rule="PROJECT_ID_TOO_LONG",
                resource="project.id",
                message=f"'{project_id}' is {len(project_id)} characters; the limit is {project_max}.",
            )
        )

    environment = deployment.environment
    if environment not in _ALLOWED_ENVIRONMENTS:
        findings.append(
            Finding(
                severity="ERROR",
                category="naming",
                rule="ENVIRONMENT_NAME_INVALID",
                resource="metadata.environment",
                message=f"'{environment}' is not one of {sorted(_ALLOWED_ENVIRONMENTS)}.",
            )
        )

    compute_max = max_len.get("compute", 63)
    reserved = set(naming.get("reserved_words", []))

    for rtype in deployment.enabled_resource_types():
        pattern = allowed_chars.get(TYPE_PATTERN_KEY.get(rtype, ""), default_pattern)
        for name, instance in deployment.instances(rtype).items():
            resource_name = instance.get("name", name) if isinstance(instance, dict) else name
            if not isinstance(resource_name, str):
                continue
            if resource_name in reserved:
                findings.append(
                    Finding(
                        severity="ERROR",
                        category="naming",
                        rule="RESERVED_NAME",
                        resource=f"{rtype}.{name}",
                        message=f"'{resource_name}' is a reserved word (config/global/naming.yaml).",
                    )
                )
            if not re.match(pattern, resource_name):
                findings.append(
                    Finding(
                        severity="WARNING",
                        category="naming",
                        rule="NAME_PATTERN_MISMATCH",
                        resource=f"{rtype}.{name}",
                        message=f"'{resource_name}' does not match the naming pattern {pattern}.",
                    )
                )
            if len(resource_name) > compute_max:
                findings.append(
                    Finding(
                        severity="ERROR",
                        category="naming",
                        rule="NAME_TOO_LONG",
                        resource=f"{rtype}.{name}",
                        message=f"'{resource_name}' is {len(resource_name)} characters; the limit is {compute_max}.",
                    )
                )

    return findings
