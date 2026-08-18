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
