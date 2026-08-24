"""Regression coverage for engine/region_engine.py, which had zero test
coverage before this. Locks in a real gap found 2026-08-24:
config/global/regions.yaml's `zone_suffixes` was defined but never
actually read anywhere — a zone's region prefix being approved was the
only check ever applied, so e.g. "asia-south1-z" passed validation even
though "z" was never an approved suffix (only a/b/c are).

Run: pytest tests/ -v
"""

from conftest import CONFIG_ROOT, FIXTURES
from engine import config_loader, region_engine


def load(fixture_name: str):
    return config_loader.load_deployment(FIXTURES / fixture_name, config_root=CONFIG_ROOT)


def test_approved_region_and_zone_suffix_pass():
    d = load("valid_minimal")
    findings = region_engine.validate_regions(d)
    assert findings == [], f"expected no findings, got: {[f.render() for f in findings]}"


def test_zone_with_unapproved_suffix_is_rejected():
    """The real bug: "asia-south1-z" has an approved region but "z" isn't
    in zone_suffixes (a/b/c) — this used to pass silently because the
    suffix was never actually checked."""
    d = load("invalid_bad_zone_suffix")
    findings = region_engine.validate_regions(d)
    assert any(f.rule == "ZONE_NOT_APPROVED" and f.resource == "vm.test-vm" for f in findings), (
        f"expected ZONE_NOT_APPROVED for vm.test-vm, got: {[f.render() for f in findings]}"
    )


def test_region_not_in_approved_list_is_rejected():
    class FakeDeployment:
        region = "us-east1"

        class global_config:
            regions = {
                "regions": {
                    "approved": ["asia-south1"],
                    "multi_region_locations": ["asia"],
                    "zone_suffixes": ["a", "b", "c"],
                }
            }

        def enabled_resource_types(self):
            return []

        def instances(self, _rtype):
            return {}

    findings = region_engine.validate_regions(FakeDeployment())
    assert any(f.rule == "REGION_NOT_APPROVED" and f.resource == "region.primary" for f in findings)
