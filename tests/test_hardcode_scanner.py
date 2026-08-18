from conftest import REPO_ROOT
from engine import hardcode_scanner


def test_real_modules_have_no_hardcoded_project_ids_or_cidrs():
    findings = hardcode_scanner.scan(REPO_ROOT)
    assert findings == [], "\n\n".join(f.render() for f in findings)


def test_scanner_catches_an_injected_hardcoded_project_id(tmp_path):
    (tmp_path / "modules").mkdir()
    bad_module = tmp_path / "modules" / "bad.tf"
    bad_module.write_text('resource "google_compute_network" "x" {\n  project = "prj-dg-devops-test"\n}\n', encoding="utf-8")

    findings = hardcode_scanner.scan(tmp_path)

    assert len(findings) == 1
    assert findings[0].rule == "PROJECT_ID_LITERAL"
    assert findings[0].line == 2


def test_scanner_respects_allow_marker(tmp_path):
    (tmp_path / "modules").mkdir()
    ok_module = tmp_path / "modules" / "ok.tf"
    ok_module.write_text(
        'resource "google_compute_network" "x" {\n'
        '  project = "prj-dg-devops-test" # hardcode-allow: test fixture only\n'
        "}\n",
        encoding="utf-8",
    )

    findings = hardcode_scanner.scan(tmp_path)

    assert findings == []
