"""Proves the validation engine both accepts good config and rejects bad
config, per the platform spec's explicit requirement: create an invalid
config, show validation rejects it; create a valid one, show it passes.

Run: pytest tests/ -v
"""

from pathlib import Path

import pytest

from conftest import CONFIG_ROOT, FIXTURES
from engine import config_loader, dependency_engine, schema_validator, security_engine
from engine.cli import run_validation


def load(fixture_name: str):
    return config_loader.load_deployment(FIXTURES / fixture_name, config_root=CONFIG_ROOT)


# --- real environments --------------------------------------------------

@pytest.mark.parametrize("env", ["dev", "sit", "uat", "prod"])
def test_real_environment_passes(env):
    report = run_validation(CONFIG_ROOT / "environments" / env)
    assert not report.blocked, report.render()


# --- valid fixture --------------------------------------------------------

def test_valid_minimal_passes():
    d = load("valid_minimal")
    findings = (
        schema_validator.validate_required_fields(d)
        + dependency_engine.validate_type_dependencies(d)
        + dependency_engine.validate_instance_references(d)
        + security_engine.validate_security(d)
    )
    errors = [f for f in findings if f.severity == "ERROR"]
    assert errors == [], f"expected no errors, got: {[e.render() for e in errors]}"


# --- invalid fixtures: each must be rejected -------------------------------

def test_vm_without_network_is_rejected():
    """The scenario the spec calls out explicitly: a VM with no network
    dependency must be blocked, with VM_NETWORK_REQUIRED naming the missing
    fields and the dependency engine naming the disabled `subnet` type."""
    d = load("invalid_missing_network")

    required_field_findings = schema_validator.validate_required_fields(d)
    assert any(f.rule == "VM_NETWORK_REQUIRED" for f in required_field_findings)
    vm_finding = next(f for f in required_field_findings if f.rule == "VM_NETWORK_REQUIRED")
    assert "subnet" in vm_finding.missing
    assert "service_account.name" in vm_finding.missing
    assert "boot_disk.image" in vm_finding.missing

    dependency_findings = dependency_engine.validate_type_dependencies(d)
    assert any(f.rule == "VM_DEPENDENCY_MISSING" for f in dependency_findings)


def test_invalid_reference_is_rejected():
    d = load("invalid_bad_reference")
    findings = dependency_engine.validate_instance_references(d)
    assert any(f.rule == "INVALID_REFERENCE" and f.resource == "vm.test-vm" for f in findings)


def test_cloudsql_password_secret_typo_is_rejected():
    """Real gap found 2026-08-25: cloudsql.users.<user>.password_secret is
    a genuine instance-key reference into secrets (var.passwords[secret_name]
    in modules/database/cloudsql/main.tf), but was never checked — a typo
    would have passed validation cleanly and crashed terraform plan/apply
    with a raw "Invalid index" error instead."""

    class FakeDeployment:
        def enabled_resource_types(self):
            return ["cloudsql", "secrets"]

        def instances(self, rtype):
            if rtype == "cloudsql":
                return {"app-sql": {"users": {"root": {"password_secret": "typo-password"}}}}
            if rtype == "secrets":
                return {"mysql-root-password": {}}
            return {}

    findings = dependency_engine.validate_instance_references(FakeDeployment())
    assert any(
        f.rule == "INVALID_REFERENCE" and f.resource == "cloudsql.app-sql.users.root" for f in findings
    ), [f.render() for f in findings]


def test_cloudsql_password_secret_valid_reference_passes():
    class FakeDeployment:
        def enabled_resource_types(self):
            return ["cloudsql", "secrets"]

        def instances(self, rtype):
            if rtype == "cloudsql":
                return {"app-sql": {"users": {"root": {"password_secret": "mysql-root-password"}}}}
            if rtype == "secrets":
                return {"mysql-root-password": {}}
            return {}

    findings = dependency_engine.validate_instance_references(FakeDeployment())
    assert findings == [], [f.render() for f in findings]


def test_pubsub_dead_letter_topic_typo_is_rejected():
    """Same class of gap: pubsub's dead_letter_policy.topic self-references
    another pubsub topic instance (google_pubsub_topic.topic[...] in
    modules/messaging/pubsub/main.tf) but was never checked either."""

    class FakeDeployment:
        def enabled_resource_types(self):
            return ["pubsub"]

        def instances(self, rtype):
            return {
                "app-events": {
                    "subscriptions": {
                        "app-events-sub": {"dead_letter_policy": {"topic": "typo-topic"}},
                    }
                }
            }

    findings = dependency_engine.validate_instance_references(FakeDeployment())
    assert any(
        f.rule == "INVALID_REFERENCE" and f.resource == "pubsub.app-events.subscriptions.app-events-sub"
        for f in findings
    ), [f.render() for f in findings]


def test_iap_missing_target_vm_is_rejected():
    """Real gap found 2026-08-25: iap had no RESOURCE_RULES entry at all,
    and modules/security/iap/main.tf accesses cfg.target_vm/cfg.members
    directly with no fallback — an omitted field would crash
    terraform plan with a raw "Unsupported attribute" error instead of a
    clean validation message."""

    class FakeDeployment:
        def enabled_resource_types(self):
            return ["iap"]

        def instances(self, rtype):
            return {"admin-access": {"members": []}}  # target_vm omitted

    findings = schema_validator.validate_required_fields(FakeDeployment())
    assert any(f.resource == "iap.admin-access" and "target_vm" in f.missing for f in findings), [
        f.render() for f in findings
    ]


def test_iap_with_empty_members_list_is_not_flagged():
    """members: [] (present, deliberately empty — "wiring is live, access
    is closed by default", see docs/security.md) must still pass; only an
    entirely absent members key should be caught."""

    class FakeDeployment:
        def enabled_resource_types(self):
            return ["iap"]

        def instances(self, rtype):
            return {"admin-access": {"target_vm": "app-vm-01", "members": []}}

    findings = schema_validator.validate_required_fields(FakeDeployment())
    assert findings == [], [f.render() for f in findings]


def test_workload_identity_missing_fields_are_rejected():
    class FakeDeployment:
        def enabled_resource_types(self):
            return ["workload_identity"]

        def instances(self, rtype):
            return {"app-workload": {"gcp_service_account": "app-workload-sa"}}  # k8s fields omitted

    findings = schema_validator.validate_required_fields(FakeDeployment())
    assert any(
        f.resource == "workload_identity.app-workload"
        and "k8s_namespace" in f.missing
        and "k8s_service_account" in f.missing
        for f in findings
    ), [f.render() for f in findings]


def test_cloudrun_no_deletion_protection_is_rejected():
    """Real gap found 2026-08-25: config/global/security.yaml's
    policy.deletion_protection_required_for listed cloudrun, but no check
    for it existed anywhere — the real dev config relied on that gap
    (deletion_protection: false) before this was fixed alongside adding
    the SEC_CLOUDRUN_NO_DELETION_PROTECTION rule."""

    class FakeDeployment:
        class global_config:
            security = {
                "policy": {"deletion_protection_required_for": ["cloudsql", "cloudrun"]},
                "rules": [],
            }

        def enabled_resource_types(self):
            return ["cloudrun"]

        def instances(self, rtype):
            return {"app-api": {"deletion_protection": False}} if rtype == "cloudrun" else {}

    findings = security_engine.validate_security(FakeDeployment())
    assert any(
        f.rule == "SEC_CLOUDRUN_NO_DELETION_PROTECTION" and f.resource == "cloudrun.app-api" for f in findings
    ), [f.render() for f in findings]


def test_cloudrun_with_deletion_protection_passes():
    class FakeDeployment:
        class global_config:
            security = {
                "policy": {"deletion_protection_required_for": ["cloudsql", "cloudrun"]},
                "rules": [],
            }

        def enabled_resource_types(self):
            return ["cloudrun"]

        def instances(self, rtype):
            return {"app-api": {"deletion_protection": True}} if rtype == "cloudrun" else {}

    findings = security_engine.validate_security(FakeDeployment())
    assert findings == [], [f.render() for f in findings]


def test_public_ssh_firewall_is_rejected():
    d = load("invalid_public_ssh")
    findings = security_engine.validate_security(d)
    assert any(f.rule == "SEC_PUBLIC_SSH" for f in findings)


def test_dependency_cycle_is_detected():
    class FakeGlobalConfig:
        dependencies = {
            "dependencies": {
                "a": {"requires": ["b"]},
                "b": {"requires": ["a"]},
            }
        }

    findings = dependency_engine.validate_dependency_graph_integrity(FakeGlobalConfig())
    assert any(f.rule == "DEPENDENCY_CYCLE" for f in findings)


def test_real_dependency_graph_has_no_cycles():
    gc = config_loader.GlobalConfig.load(CONFIG_ROOT)
    findings = dependency_engine.validate_dependency_graph_integrity(gc)
    assert findings == []


def test_yaml_syntax_error_is_reported(tmp_path):
    env_dir = tmp_path / "broken"
    env_dir.mkdir()
    (env_dir / "deployment.yaml").write_text("resources: [this is not: valid yaml", encoding="utf-8")
    with pytest.raises(config_loader.ConfigError):
        config_loader.load_deployment(env_dir, config_root=CONFIG_ROOT)
