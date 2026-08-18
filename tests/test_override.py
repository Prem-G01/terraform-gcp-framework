"""Proves the --force-security break-glass mechanism in engine/cli.py:
- normal render still blocks on a security error
- --force-security requires --reason (enforced by argparse in main(), not
  re-tested here — see the two cmd_render-level checks below)
- --force-security forces through ONLY security-category errors, writes an
  audit record, and refuses outright if any non-security error is present
"""

import argparse
import json
import shutil
from pathlib import Path

from conftest import CONFIG_ROOT, FIXTURES
from engine.cli import cmd_render


def _make_env(tmp_path: Path, deployment_yaml: str) -> Path:
    """Builds a tmp_path/config/environments/testenv/ pointed at the real
    config/global/ (copied), so cmd_render's env_dir.parent.parent ->
    config_root inference works exactly like it does for a real environment."""
    config_root = tmp_path / "config"
    shutil.copytree(CONFIG_ROOT / "global", config_root / "global")
    shutil.copytree(CONFIG_ROOT / "schema", config_root / "schema")
    env_dir = config_root / "environments" / "testenv"
    env_dir.mkdir(parents=True)
    (env_dir / "deployment.yaml").write_text(deployment_yaml, encoding="utf-8")
    return env_dir


_SECURITY_ONLY_VIOLATION = """\
apiVersion: platform.gcp/v1
kind: Deployment
metadata:
  name: fixture
  environment: dev
  owner: devops
project:
  id: prj-dg-devops-test
region:
  primary: asia-south1
resources:
  vpc:
    enabled: true
    instances:
      test-vpc:
        auto_create_subnetworks: false
        routing_mode: GLOBAL
  firewall:
    enabled: true
    instances:
      allow-ssh-everywhere:
        network: test-vpc
        direction: INGRESS
        source_ranges: ["0.0.0.0/0"]
        allow:
          - protocol: tcp
            ports: ["22"]
"""

_NON_SECURITY_VIOLATION = """\
apiVersion: platform.gcp/v1
kind: Deployment
metadata:
  name: fixture
  environment: dev
  owner: devops
project:
  id: prj-dg-devops-test
region:
  primary: asia-south1
resources:
  subnet:
    enabled: false
    instances: {}
  vm:
    enabled: true
    instances:
      test-vm:
        machine_type: e2-medium
"""


def test_force_security_bypasses_a_security_only_error(tmp_path):
    env_dir = _make_env(tmp_path, _SECURITY_ONLY_VIOLATION)
    out_path = tmp_path / "out" / "deployment.normalized.json"

    rc = cmd_render(argparse.Namespace(env_dir=env_dir, out=out_path, force_security=True, reason="testing the override"))

    assert rc == 0
    assert out_path.is_file()
    audit_path = out_path.parent / "override-audit.jsonl"
    assert audit_path.is_file()
    record = json.loads(audit_path.read_text(encoding="utf-8").splitlines()[-1])
    assert record["reason"] == "testing the override"
    assert any(f["rule"] == "SEC_PUBLIC_SSH" for f in record["overridden_findings"])


def test_force_security_still_blocks_without_reason_check_at_argparse_level():
    """--reason enforcement lives in main(), not cmd_render — this documents
    that cmd_render itself doesn't re-check it, so main() must always be
    the entry point for real use, never cmd_render called directly with
    force_security=True and no reason from other code."""
    import inspect

    from engine.cli import main

    source = inspect.getsource(main)
    assert '"--force-security requires --reason' in source


def test_force_security_refuses_when_non_security_errors_present(tmp_path):
    env_dir = _make_env(tmp_path, _NON_SECURITY_VIOLATION)
    out_path = tmp_path / "out" / "deployment.normalized.json"

    rc = cmd_render(argparse.Namespace(env_dir=env_dir, out=out_path, force_security=True, reason="should not work"))

    assert rc == 1
    assert not out_path.exists()


def test_normal_render_without_force_still_blocks_on_security_error(tmp_path):
    env_dir = _make_env(tmp_path, _SECURITY_ONLY_VIOLATION)
    out_path = tmp_path / "out" / "deployment.normalized.json"

    rc = cmd_render(argparse.Namespace(env_dir=env_dir, out=out_path, force_security=False, reason=None))

    assert rc == 1
    assert not out_path.exists()
