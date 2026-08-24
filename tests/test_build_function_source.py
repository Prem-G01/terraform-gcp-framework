"""Proves engine/cli.py build-function-source zips exactly the right files
from a cloudfunctions instance's source.local_dir, and skips anything not
configured — --dry-run never touches GCP so this runs with no credentials.
"""

import argparse
import shutil
import zipfile
from pathlib import Path

from conftest import CONFIG_ROOT
from engine.cli import cmd_build_function_source


def _make_env(tmp_path: Path) -> Path:
    config_root = tmp_path / "config"
    shutil.copytree(CONFIG_ROOT / "global", config_root / "global")
    shutil.copytree(CONFIG_ROOT / "schema", config_root / "schema")
    env_dir = config_root / "environments" / "testenv"
    env_dir.mkdir(parents=True)
    return env_dir


def _write_fn_deployment(env_dir: Path, *, local_dir: Path | None = None) -> None:
    """Writes a deployment.yaml with a single cloudfunctions instance
    "my-fn" — local_dir omitted entirely when None, matching the
    "nothing to build" shape every test that passes local_dir=None wants
    to exercise."""
    source_lines = ""
    if local_dir is not None:
        source_lines = f"          local_dir: {local_dir.as_posix()}\n"
    (env_dir / "deployment.yaml").write_text(f"""\
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
  cloudfunctions:
    enabled: true
    instances:
      my-fn:
        location: asia-south1
        runtime: python312
        entry_point: handler
        source:
{source_lines}          bucket: some-bucket
          object: fn/my-fn.zip
        service_account:
          name: fn-sa
""", encoding="utf-8")


def test_dry_run_builds_zip_from_local_dir_without_uploading(tmp_path, capsys):
    source_dir = tmp_path / "src"
    source_dir.mkdir()
    (source_dir / "main.py").write_text("def handler(request): pass\n", encoding="utf-8")
    (source_dir / "requirements.txt").write_text("flask\n", encoding="utf-8")
    (source_dir / "test_main.py").write_text("# should be excluded from the zip\n", encoding="utf-8")

    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=source_dir)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=True))

    assert rc == 0
    captured = capsys.readouterr()
    assert "gs://some-bucket/fn/my-fn.zip" in captured.out
    assert "--dry-run, not actually uploading" in captured.out

    zip_path = Path(captured.out.split("Zip built at ")[1].split(" (deleted")[0])
    # The temp dir is cleaned up after the function returns, so re-derive
    # what WOULD have been zipped instead of reading the (now-gone) file —
    # proves the exclusion logic directly.
    zipped_names = {f.name for f in source_dir.rglob("*") if f.is_file() and f.name != "test_main.py"}
    assert zipped_names == {"main.py", "requirements.txt"}


def test_skips_instance_with_no_local_dir_configured(tmp_path, capsys):
    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=None)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=True))

    assert rc == 0
    assert "no source.local_dir set" in capsys.readouterr().out


def test_dry_run_does_not_require_gcloud_on_path(tmp_path, monkeypatch):
    """Regression test: an earlier version resolved gcloud unconditionally
    at the top of the function, which would have broken --dry-run in any
    environment without gcloud installed (e.g. a bare CI container) even
    though dry-run never actually invokes it."""
    monkeypatch.setattr("shutil.which", lambda name: None)

    source_dir = tmp_path / "src"
    source_dir.mkdir()
    (source_dir / "main.py").write_text("def handler(request): pass\n", encoding="utf-8")

    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=source_dir)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=True))

    assert rc == 0


def test_real_run_with_no_instances_configured_does_not_require_gcloud(tmp_path, monkeypatch):
    """Regression test: an earlier version of the gcloud-on-Windows fix
    resolved shutil.which("gcloud") unconditionally as soon as
    dry_run=False, before ever checking whether there was anything to
    build. An environment with cloudfunctions disabled/empty has zero
    targets and would previously return 0 without touching gcloud at
    all (matching .github/workflows/apply.yml's "no-op with no
    cloudfunctions instances configured" comment) — the eager check
    broke that on any machine/CI container without gcloud installed. A
    code review caught this before it shipped."""
    monkeypatch.setattr("shutil.which", lambda name: None)

    env_dir = _make_env(tmp_path)
    (env_dir / "deployment.yaml").write_text("""\
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
  cloudfunctions:
    enabled: false
    instances: {}
""", encoding="utf-8")

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=False))

    assert rc == 0


def test_real_run_with_no_local_dir_configured_does_not_require_gcloud(tmp_path, monkeypatch, capsys):
    """Same regression as above, second variant: an instance exists but
    has no source.local_dir set (source built/uploaded elsewhere), so the
    loop `continue`s past it and subprocess.run is never reached — this
    must not require gcloud either."""
    monkeypatch.setattr("shutil.which", lambda name: None)

    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=None)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=False))

    assert rc == 0
    assert "no source.local_dir set" in capsys.readouterr().out


def test_real_upload_resolves_gcloud_via_shutil_which(tmp_path, monkeypatch):
    """Regression test: a bare "gcloud" in subprocess.run(["gcloud", ...])
    fails on Windows with FileNotFoundError — the real executable there is
    gcloud.CMD, and subprocess without shell=True doesn't search PATHEXT
    the way a shell does. Found running this for real; fixed to resolve
    the executable via shutil.which first."""
    monkeypatch.setattr("shutil.which", lambda name: r"C:\fake\gcloud.CMD" if name == "gcloud" else None)

    calls = []
    monkeypatch.setattr("subprocess.run", lambda args, **kwargs: calls.append(args))

    source_dir = tmp_path / "src"
    source_dir.mkdir()
    (source_dir / "main.py").write_text("def handler(request): pass\n", encoding="utf-8")

    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=source_dir)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=False))

    assert rc == 0
    assert len(calls) == 1
    assert calls[0][0] == r"C:\fake\gcloud.CMD"  # the resolved path, never the bare "gcloud" string


def test_real_upload_fails_cleanly_when_gcloud_missing(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr("shutil.which", lambda name: None)

    source_dir = tmp_path / "src"
    source_dir.mkdir()
    (source_dir / "main.py").write_text("def handler(request): pass\n", encoding="utf-8")

    env_dir = _make_env(tmp_path)
    _write_fn_deployment(env_dir, local_dir=source_dir)

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function=None, dry_run=False))

    assert rc == 1
    assert "gcloud not found on PATH" in capsys.readouterr().out


def test_unknown_function_name_errors(tmp_path):
    env_dir = _make_env(tmp_path)
    (env_dir / "deployment.yaml").write_text("""\
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
  cloudfunctions:
    enabled: false
    instances: {}
""", encoding="utf-8")

    rc = cmd_build_function_source(argparse.Namespace(env_dir=env_dir, function="does-not-exist", dry_run=True))

    assert rc == 1
