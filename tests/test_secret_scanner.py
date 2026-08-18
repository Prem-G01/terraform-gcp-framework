from conftest import REPO_ROOT
from engine import secret_scanner


def test_real_repo_has_no_leaked_secrets():
    findings = secret_scanner.scan(REPO_ROOT)
    assert findings == [], "\n\n".join(f.render() for f in findings)


def test_scanner_does_not_flag_its_own_source():
    """Regression test: the scanner's own pattern definitions and
    docstring mention field names like `"private_key"` and `"type":
    "service_account"` — an earlier, cruder version of this scanner
    matched on the field name alone and flagged itself."""
    findings = secret_scanner.scan(REPO_ROOT / "engine")
    assert findings == []


def test_catches_a_pem_private_key(tmp_path):
    fake_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----\n"  # secret-allow: fabricated test fixture, not a real key
    (tmp_path / "leaked.pem").write_text(fake_key, encoding="utf-8")
    findings = secret_scanner.scan(tmp_path)
    assert any(f.rule == "PEM_PRIVATE_KEY" for f in findings)


def test_catches_a_real_shaped_gcp_service_account_key(tmp_path):
    fake_key_json = '{"type": "service_account", "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIExample\\n-----END PRIVATE KEY-----\\n"}'  # secret-allow: fabricated test fixture, not a real key
    (tmp_path / "key.json").write_text(fake_key_json, encoding="utf-8")
    findings = secret_scanner.scan(tmp_path)
    assert any(f.rule == "GCP_SERVICE_ACCOUNT_KEY_FILE" for f in findings)


def test_does_not_flag_a_field_merely_named_private_key(tmp_path):
    """The field name alone, without real PEM content in the value, must
    not fire — this is exactly the false positive that motivated
    requiring the PEM header inside the value."""
    (tmp_path / "schema.md").write_text(
        'Set `"private_key"` to your key content when building a `"type": "service_account"` credential file.',
        encoding="utf-8",
    )
    findings = secret_scanner.scan(tmp_path)
    assert findings == []


def test_catches_an_aws_access_key_id(tmp_path):
    fake_key_id = "AKIAIOSFODNN7EXAMPLE"  # secret-allow: AWS's own published example key, not a real one
    (tmp_path / "notes.txt").write_text(f"aws_access_key_id = {fake_key_id}\n", encoding="utf-8")
    findings = secret_scanner.scan(tmp_path)
    assert any(f.rule == "AWS_ACCESS_KEY_ID" for f in findings)


def test_scanner_respects_allow_marker(tmp_path):
    fake_key_id = "AKIAIOSFODNN7EXAMPLE"  # secret-allow: AWS's own published example key, not a real one
    (tmp_path / "notes.txt").write_text(
        f"aws_access_key_id = {fake_key_id}  # secret-allow: documented public AWS example key\n",
        encoding="utf-8",
    )
    findings = secret_scanner.scan(tmp_path)
    assert findings == []
