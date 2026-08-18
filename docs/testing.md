# Testing

## What's actually run (and passing, as of this rebuild)

```bash
pytest tests/ -v                          # 14 passed
terraform fmt -check -recursive .          # clean
python -m engine.cli validate-all config   # dev/sit/uat/prod all PASS
python -m engine.cli hardcode-scan .       # 0 findings
cd environments/dev && terraform init -backend=false && terraform validate  # Success
cd environments/dev && terraform plan      # (with a real backend configured) 99 to add, 0 errors
```

The `terraform plan` above was run twice, manually, against the real
`prj-dg-devops-test` project with a temporary local-backend override
(never committed — see `docs/troubleshooting.md`) purely to prove the
configuration evaluates with no runtime errors. It was **not** followed by
`apply` — nothing was created. The first run (25 resource types, 82
resources) caught one real bug (`modules/security/kms/main.tf` referenced
a `kr.name` field that no longer exists in the consolidated config —
fixed by removing the unused local). The second run, after adding GKE,
Cloud Functions, Memorystore, and VPC Service Controls (29 resource
types, 99 resources — `vpc_service_controls` stays disabled by default so
contributes 0), caught a second real bug: `engine/region_engine.py`
rejected GKE's zonal `location` field (e.g. `asia-south1-a`) because it
only recognized bare regions there — fixed to accept a zone within an
approved region too.

## Test suite (`tests/`)

| Test | Proves |
|---|---|
| `test_real_environment_passes[dev\|sit\|uat\|prod]` | every real `config/environments/<env>/deployment.yaml` validates clean |
| `test_valid_minimal_passes` | a correctly-wired vpc+subnet+service_account+vm fixture has zero errors |
| `test_vm_without_network_is_rejected` | **the spec's explicit ask**: a VM with no subnet is rejected, naming `subnet`, `service_account.name`, `boot_disk.image` as missing, and flagging the disabled `subnet` dependency |
| `test_invalid_reference_is_rejected` | a `vm.subnet` field pointing at a nonexistent subnet instance fails `INVALID_REFERENCE` |
| `test_public_ssh_firewall_is_rejected` | a firewall rule opening TCP/22 to 0.0.0.0/0 fails `SEC_PUBLIC_SSH` |
| `test_dependency_cycle_is_detected` | a synthetic `a requires b, b requires a` graph is caught |
| `test_real_dependency_graph_has_no_cycles` | the real `config/global/dependencies.yaml` is acyclic |
| `test_yaml_syntax_error_is_reported` | malformed YAML raises `ConfigError` rather than crashing |
| `test_real_modules_have_no_hardcoded_project_ids_or_cidrs` | `modules/`, `platform/`, `bootstrap/` are clean per the hardcode scanner |
| `test_scanner_catches_an_injected_hardcoded_project_id` | the scanner actually detects a planted violation |
| `test_scanner_respects_allow_marker` | `# hardcode-allow:` suppression works |

Run `pytest tests/ -v` — no GCP credentials, no network access, and no
`.tfstate` required; the whole suite runs in well under a second because
`engine/` makes zero GCP API calls by design (see
[docs/validation.md](validation.md) "Cost validation — an honest
limitation" for the one place that trade-off is most visible).

## What's not tested

- **Integration**: no test actually runs `terraform apply` against a real
  or ephemeral GCP project. Doing that safely needs a disposable sandbox
  project, its own budget alert, and teardown automation — none of which
  exists here (see [docs/troubleshooting.md](troubleshooting.md)).
- **Cloud Build pipelines**: `cicd/*.yaml` is unexercised — no build has
  actually run it (no connected git remote/trigger in this environment).
- **`modules/` resource-attribute correctness** beyond what `terraform
  plan` against the real dev config already exercised once, manually —
  there's no per-module unit test framework (e.g. Terratest) in this repo.
