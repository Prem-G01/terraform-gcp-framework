"""Regression coverage for engine/naming_engine.py, which had zero test
coverage before this. Locks in a real gap found 2026-08-24:
config/global/naming.yaml's max_length.sql_instance (98) and
.bigquery_dataset (1024) were defined but never actually read — every
resource type was checked against a single hardcoded compute limit (63)
regardless of its own declared max_length, so a real BigQuery dataset
name between 64 and 1024 characters (valid per both GCP and this
platform's own config) would have been wrongly rejected as
NAME_TOO_LONG.

Run: pytest tests/ -v
"""

from engine import naming_engine


class FakeDeployment:
    raw = {"project": {"id": "prj-dg-devops-test"}}
    environment = "dev"

    class global_config:
        naming = {
            "naming": {
                "max_length": {
                    "default": 63,
                    "compute": 63,
                    "bucket": 63,
                    "sql_instance": 98,
                    "bigquery_dataset": 1024,
                    "project_id": 30,
                },
                "allowed_characters": {
                    "default": "^[a-z][a-z0-9-]*[a-z0-9]$",
                    "bucket": "^[a-z0-9][a-z0-9._-]*[a-z0-9]$",
                    "bigquery_dataset": "^[a-zA-Z0-9_]+$",
                },
                "reserved_words": ["google", "ssl-vip", "test"],
            }
        }

    def __init__(self, instances_by_type):
        self._instances_by_type = instances_by_type

    def enabled_resource_types(self):
        return list(self._instances_by_type)

    def instances(self, rtype):
        return self._instances_by_type.get(rtype, {})


def test_bigquery_dataset_name_within_its_own_1024_limit_is_not_rejected():
    """The real bug: a 100-character name is well within bigquery_dataset's
    real 1024 limit but exceeds compute's 63 — must not be flagged."""
    long_name = "a" * 100
    d = FakeDeployment({"bigquery": {long_name: {}}})
    findings = naming_engine.validate_naming(d)
    assert not any(f.rule == "NAME_TOO_LONG" for f in findings), [f.render() for f in findings]


def test_cloudsql_instance_name_within_its_own_98_limit_is_not_rejected():
    long_name = "b" * 80
    d = FakeDeployment({"cloudsql": {long_name: {}}})
    findings = naming_engine.validate_naming(d)
    assert not any(f.rule == "NAME_TOO_LONG" for f in findings), [f.render() for f in findings]


def test_a_type_with_no_override_still_uses_the_compute_default_of_63():
    """Types without an explicit max_length entry (e.g. vm) must still
    fall back to the compute/default limit — the fix must not accidentally
    make every type unlimited."""
    over_default = "c" * 70
    d = FakeDeployment({"vm": {over_default: {}}})
    findings = naming_engine.validate_naming(d)
    assert any(f.rule == "NAME_TOO_LONG" and f.resource == f"vm.{over_default}" for f in findings), [
        f.render() for f in findings
    ]


def test_bucket_name_over_1024_is_still_rejected_at_its_own_limit():
    """bucket's own max_length (63) must still be enforced — the fix must
    use each type's own limit, not just always fall back to the highest
    one available."""
    over_bucket_limit = "d" * 64
    d = FakeDeployment({"buckets": {over_bucket_limit: {}}})
    findings = naming_engine.validate_naming(d)
    assert any(f.rule == "NAME_TOO_LONG" and f.resource == f"buckets.{over_bucket_limit}" for f in findings), [
        f.render() for f in findings
    ]
