# Testing

## What's actually run (and passing, as of this rebuild)

```bash
pytest tests/ -v                                    # 25 passed
pytest functions/process-upload/test_main.py -v     # 3 passed, no GCP call
terraform fmt -check -recursive .                    # clean
python -m engine.cli validate-all config             # dev/sit/uat/prod all PASS
python -m engine.cli hardcode-scan .                 # 0 findings
python -m engine.cli build-function-source config/environments/dev --dry-run
cd environments/dev && terraform init -backend=false && terraform validate  # Success
cd environments/dev && terraform plan      # (with a real backend configured) 99 to add, 0 errors
cd platform && terraform test                                # 2 passed, mock_provider, no GCP call
cd modules/database/cloudsql && terraform test                # 2 passed, mock_provider, no GCP call
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
| `test_interpolate_replaces_known_tokens` / `..._resolves_tokens_to_real_values` | `{project_id}`/`{region}`/`{environment}`/`{owner}` interpolation (see `docs/configuration.md`) |
| `test_force_security_bypasses_a_security_only_error` / `..._refuses_when_non_security_errors_present` | the `--force-security` break-glass override (see `docs/validation.md`) |
| `test_dry_run_builds_zip_from_local_dir_without_uploading` | `build-function-source` zips the right files and excludes `test_main.py` |
| `functions/process-upload/test_main.py` (separate suite, not under `tests/`) | the actual Cloud Function handler logic — valid/invalid payloads, no GCP call |

Run `pytest tests/ -v` — no GCP credentials, no network access, and no
`.tfstate` required; the whole suite runs in well under a second because
`engine/` makes zero GCP API calls by design (see
[docs/validation.md](validation.md) "Cost validation — an honest
limitation" for the one place that trade-off is most visible).

## Native Terraform tests (`*.tftest.hcl`)

Terraform's built-in `terraform test` framework (>= 1.7) runs module-level
tests with `mock_provider "google" {}` — every GCP API call is faked, so
these run with no credentials, no network access, and touch nothing real:

| File | Proves |
|---|---|
| `platform/tests/count_gating.tftest.hcl` | an empty `resources` block enables nothing; enabling one type (`buckets`) doesn't leak into any other |
| `modules/database/cloudsql/tests/sql_user_creation.tftest.hcl` | `google_sql_user` is actually created for every configured user — direct regression coverage for the real bug this rebuild found (the original module computed the user list but never created the resource) |

Run from the module directory itself: `cd platform && terraform test`, or
`cd modules/database/cloudsql && terraform test` (each needs its own
`terraform init` first, same as any root module — these two directories
are the only ones set up to run standalone).

**Why so little coverage, out of 29 resource types?** These two exist to
demonstrate the pattern and to lock in the one bug this rebuild actually
found and fixed — not as a claim that every module is covered. Extending
this to the rest of `modules/` is real, valuable, unfinished work — see
"What's not tested" below.

**A real limitation of `mock_provider`, hit while writing these**: it
still enforces the real provider schema's field-level validation (regexes,
etc.), even though every value is faked. A mocked resource's computed
attribute (e.g. a VPC's `self_link`) is a plausible-looking random string,
not a real-shaped URL — feeding that into another resource's field that
expects a URL pattern (e.g. Cloud SQL's `private_network`) fails validation
under `mock_provider` even though the same wiring is correct against real
GCP. `platform/tests/count_gating.tftest.hcl` avoids this by testing a
resource type (`buckets`) with no such cross-module reference; testing a
type that does chain through another module's computed output would need
an explicit `override_resource` block to give the referenced value a
realistic shape.

## What's not tested

- **Integration**: no test actually runs `terraform apply` against a real
  or ephemeral GCP project. Doing that safely needs a disposable sandbox
  project, its own budget alert, and teardown automation — none of which
  exists here (see [docs/troubleshooting.md](troubleshooting.md)).
- **Cloud Build pipelines**: `cicd/*.yaml` is unexercised — no build has
  actually run it (no connected git remote/trigger in this environment).
- **Most of `modules/`** still has no dedicated `.tftest.hcl` — only
  `cloudsql` does. The one real `terraform plan`/`apply` against the real
  dev config (see above) is the only cross-module exercise the other 27
  types have had.
