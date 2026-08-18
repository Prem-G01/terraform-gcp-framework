# Testing

## What's actually run (and passing, as of this rebuild)

```bash
pytest tests/ -v                                    # 44 passed
pytest functions/process-upload/test_main.py -v     # 3 passed, no GCP call
terraform fmt -check -recursive .                    # clean
python -m engine.cli validate-all config             # dev/sit/uat/prod all PASS
python -m engine.cli hardcode-scan .                 # 0 findings
python -m engine.cli secret-scan .                   # 0 findings
python -m engine.cli build-function-source config/environments/dev --dry-run
cd environments/dev && terraform init -backend=false && terraform validate  # Success
cd environments/dev && terraform plan      # (with a real backend configured) 99 to add, 0 errors
cd platform && terraform test                                # 5 passed, mock_provider, no GCP call
cd modules/database/cloudsql && terraform test                # 2 passed, mock_provider, no GCP call
cd modules/security/workload_identity && terraform test       # 2 passed, mock_provider, no GCP call

# Live Cloud Billing check — the one command anywhere in this repo that
# makes a real GCP API call. Not part of the suite above on purpose.
pip install -r engine/requirements-live-cost.txt
python -m engine.cli cost-check-live config/environments/dev
# Actually run against the real prj-dg-devops-test project while writing
# this feature: e2-medium correctly fell back to the static table (shared-
# core, not live-priced), db-custom-2-4096 correctly stayed static (Cloud
# SQL unsupported), total $99.28/mo, within the $300/mo dev threshold.
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
| `test_live_cost.py` (9 tests) | `engine/live_cost.py`'s shape parsing (`e2-standard-4` accepted, `e2-medium`/custom/unknown rejected), SKU-matching (region match, excludes Custom/Preemptible/Sole-Tenancy variants), and the core+RAM price formula — all with synthetic SKU data, no real API call (see "Live cost check" below) |
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
| `platform/tests/count_gating.tftest.hcl` (5 runs) | an empty `resources` block enables nothing; enabling `buckets` doesn't leak into any other type; `org_policies` respects a per-constraint toggle (`restrict_public_sql_ips: false` in the fixture is NOT in `org_policies_enforced`); an `iap` binding's `target_vm` resolves to the real `google_compute_instance` name via cross-module reference, not the config key; `binary_authorization`'s `evaluation_mode` output matches the fixture |
| `modules/database/cloudsql/tests/sql_user_creation.tftest.hcl` | `google_sql_user` is actually created for every configured user — direct regression coverage for the real bug this rebuild found (the original module computed the user list but never created the resource) |
| `modules/security/workload_identity/tests/binding.tftest.hcl` | the binding grants exactly `roles/iam.workloadIdentityUser`, `member` is the `project.svc.id.goog[namespace/ksa]` form GKE Workload Identity expects, and `service_account_id` resolves to the real GCP SA from config — plus a zero-instances case creates zero bindings |

Run from the module directory itself: `cd platform && terraform test`, or
`cd modules/database/cloudsql && terraform test` (each needs its own
`terraform init` first, same as any root module — these three directories
are the only ones set up to run standalone).

**Why so little coverage, out of 33 resource types?** These exist to
demonstrate the pattern and to lock in real bugs/regressions this rebuild
actually found — not as a claim that every module is covered. Extending
this to the rest of `modules/` is real, valuable, unfinished work — see
"What's not tested" below.

**A real limitation of `mock_provider`, hit while writing these**: it
still enforces the real provider schema's field-level validation (regexes,
etc.), even though every value is faked. A mocked resource's computed
attribute (e.g. a VPC's `self_link`, or a service account's `id`) is a
plausible-looking random string, not a real-shaped URL/resource-name —
feeding that into another resource's field that expects that shape (e.g.
Cloud SQL's `private_network`, or `google_service_account_iam_member
.service_account_id`) fails validation under `mock_provider` even though
the same wiring is correct against real GCP. `platform/tests
/count_gating.tftest.hcl`'s `buckets`, `org_policies`, `iap`, and
`binary_authorization` runs avoid this by testing types with no such
cross-module computed-attribute reference (`iap`'s VM `zone`/`name`
outputs are plain strings, not self_link-shaped, so that one plans fine
even though it does chain through `modules/compute/vm`).
`workload_identity` genuinely needs a real-shaped
`google_service_account.id` downstream, so its test lives in the
module's own `tests/` directory instead, with a hand-supplied
correctly-shaped `service_account_ids` variable rather than chaining
through a mocked `modules/iam/service_accounts` — same reasoning as the
`cloudsql` test's hand-supplied `vpcs`/`passwords`. An explicit
`override_resource` block is the alternative if you need the platform-
level cross-module wiring itself under test.

## Live cost check

`python -m engine.cli cost-check-live <env-dir>` (`engine/live_cost.py`)
is different from everything above: it's the one command in this repo
that makes a real Cloud Billing Catalog API call, and it was actually run
against the real `prj-dg-devops-test` project while building it — see
`docs/validation.md` "Cost validation" for the real numbers that came
back (`e2-standard-2` priced $0.0805/hr live vs. $0.0720/hr in the static
table, a real ~12% drift caught by comparing the two). `tests
/test_live_cost.py` covers its pure logic offline; the live-API path
itself has no automated test (there's nothing to assert against that
wouldn't just be re-hardcoding a price GCP could change tomorrow) —
running it by hand against a real project, as was done here, is the only
verification that actually means anything for that part.

## What's not tested

- **Integration**: no test actually runs `terraform apply` against a real
  or ephemeral GCP project. Doing that safely needs a disposable sandbox
  project, its own budget alert, and teardown automation — none of which
  exists here (see [docs/troubleshooting.md](troubleshooting.md)).
- **GitHub Actions pipelines**: `.github/workflows/*.yml` is unexercised —
  no run has actually triggered it (no connected GitHub remote in this
  environment).
- **Most of `modules/`** still has no dedicated `.tftest.hcl` — only
  `cloudsql` and `workload_identity` do, plus `platform/tests
  /count_gating.tftest.hcl`'s coverage of `buckets`, `org_policies`,
  `iap`, and `binary_authorization`. The one real `terraform plan`/
  `apply` against the real dev config (see above) is the only
  cross-module exercise the other ~27 types have had.
- **`org_policies`, `iap`, `workload_identity`, and
  `binary_authorization`** (added for the zero-trust workstream — see
  [docs/security.md](security.md)) have never been applied against a
  real project. `binary_authorization`'s `ALWAYS_DENY` default in
  particular has never been proven to actually block a real image
  deploy, only planned.
