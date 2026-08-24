# Testing

## What's actually run (and passing, as of this rebuild)

```bash
pytest tests/ -v                                    # 51 passed
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
cd modules/storage/buckets && terraform test                  # 2 passed, mock_provider, no GCP call
cd modules/compute/vm && terraform test                       # 2 passed, mock_provider, no GCP call
cd modules/security/kms && terraform test                     # 2 passed, mock_provider, no GCP call
cd modules/security/secrets && terraform test                 # 2 passed, mock_provider, no GCP call

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
| `test_region_engine.py` (3 tests) | `region_engine.py`'s zone validation — a real gap found 2026-08-24: `config/global/regions.yaml`'s `zone_suffixes` was defined but never actually read, so a zone like `asia-south1-z` passed just because its region prefix was approved, ignoring that `z` was never an approved suffix (only a/b/c are); now enforced and locked in by `test_zone_with_unapproved_suffix_is_rejected` |
| `test_real_modules_have_no_hardcoded_project_ids_or_cidrs` | `modules/`, `platform/`, `bootstrap/` are clean per the hardcode scanner |
| `test_scanner_catches_an_injected_hardcoded_project_id` | the scanner actually detects a planted violation |
| `test_scanner_respects_allow_marker` | `# hardcode-allow:` suppression works |
| `test_interpolate_replaces_known_tokens` / `..._resolves_tokens_to_real_values` | `{project_id}`/`{region}`/`{environment}`/`{owner}` interpolation (see `docs/configuration.md`) |
| `test_force_security_bypasses_a_security_only_error` / `..._refuses_when_non_security_errors_present` | the `--force-security` break-glass override (see `docs/validation.md`) |
| `test_dry_run_builds_zip_from_local_dir_without_uploading` | `build-function-source` zips the right files and excludes `test_main.py` |
| `test_live_cost.py` (11 tests) | `engine/live_cost.py`'s shape parsing (`e2-standard-4` accepted, `e2-medium`/custom/unknown rejected), SKU-matching (region match, excludes Custom/Preemptible/Sole-Tenancy variants, and the per-family description prefix — `N1 Predefined Instance ...`/`N2D AMD Instance ...`, not a uniform `<Family> Instance ...`, a real bug a code review caught), and the core+RAM price formula including N1's real 3.75 GB/vCPU ratio (not 4, another real bug the same review caught) — all with synthetic SKU data, no real API call (see "Live cost check" below) |
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
| `modules/database/cloudsql/tests/network_defaults.tftest.hcl` | `network.ipv4_enabled` defaults to `false` (no public IP) when omitted from config, and an explicit `true` is never silently overridden — regression coverage for a real gap a `security_defaults` audit found (2026-08-19, see docs/security.md) |
| `modules/security/workload_identity/tests/binding.tftest.hcl` | the binding grants exactly `roles/iam.workloadIdentityUser`, `member` is the `project.svc.id.goog[namespace/ksa]` form GKE Workload Identity expects, and `service_account_id` resolves to the real GCP SA from config — plus a zero-instances case creates zero bindings |
| `modules/storage/buckets/tests/security_defaults.tftest.hcl` | `uniform_bucket_level_access`/`public_access_prevention`/`versioning.enabled` all default to their secure values when omitted, and an explicit override is never silently upgraded back — same `security_defaults` audit finding |
| `modules/compute/vm/tests/security_defaults.tftest.hcl` | `network.public_ip` defaults to no `access_config` block (no external IP) and all three `shielded_vm.*` fields default to `true` when omitted, with an explicit `public_ip = true` never silently dropped — same audit finding |
| `modules/security/kms/tests/config_defaults.tftest.hcl` | a keyring's real GCP name falls back to its config map key when `name` is omitted (and an explicit name is never overridden); `purpose` defaults to `ENCRYPT_DECRYPT` and `rotation_period` to `7776000s` (90 days) when omitted, with explicit overrides of both preserved — KMS had zero test coverage before this despite `crypto_key` carrying `lifecycle { prevent_destroy = true }` and GCP having no API to hard-delete a key regardless (2026-08-24) |
| `modules/security/secrets/tests/deletion_protection.tftest.hcl` | `deletion_protection` defaults to `false` when omitted (a generated secret is trivially regeneratable) and an explicit `true` is never silently dropped — regression coverage for the default this rebuild added on 2026-08-19, previously untested (2026-08-24) |
| `modules/database/cloudsql/tests/deletion_protection_and_backup_defaults.tftest.hcl` | `deletion_protection` (docs claimed a `lookup()` fallback that the code never actually had) and `backup.enabled`/`backup.start_time` (never covered at all) both default to matching every real environment's config, with explicit values never overridden — real gap found 2026-08-24, see docs/security.md |
| `modules/artifact_registry/tests/cleanup_policy.tftest.hcl` | `cleanup_policy` itself is optional (no crash when omitted); `keep_count` — set to 20/10/10 across the real dev config but previously silently ignored entirely — now actually produces a `KEEP`/`most_recent_versions` cleanup policy, verified against the installed provider schema (2026-08-24) |
| `modules/iam/deploy_roles/tests/role_coverage.tftest.hcl` | every role `apply_sa_roles` needs, spot-checked against 10 real gaps an IAM audit found the same day (GKE, Cloud Tasks queue management, Memorystore, PSA, VPC-SC, Binary Authorization, Cloud Functions gen2, Document AI, IAP, Org Policies), plus a guard that `roles/editor`/`roles/owner` never creep in — a zero-resource module (locals/outputs only), no `mock_provider` needed |
| `bootstrap/grants/tests/grants.tftest.hcl` | the stack that actually wires cross-project IAM for sit/uat/prod — SA emails resolve against `central_project_id` not `spoke_project_id`, every binding targets the spoke project, binding counts match `deploy_roles` exactly, and the log sink is correctly gated and targets the real bucket; had zero coverage before, all 4 passed on the first run (2026-08-24) |

Run from the module directory itself: `cd platform && terraform test`, or
`cd modules/database/cloudsql && terraform test` (each needs its own
`terraform init` first, same as any root module — `platform/`,
`cloudsql`, `workload_identity`, `buckets`, `vm`, `kms`, and `secrets`
are the ones set up to run standalone).

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

- **No automated test runs `terraform apply`** — but this *has* been done
  by hand, twice, against the real `prj-dg-devops-test` project (112-117
  of `environments/dev`'s resources, plus `bootstrap/` including a real
  WIF-enabled apply on 2026-08-24) — see
  [docs/troubleshooting.md](troubleshooting.md). Nothing is currently
  left live from `environments/dev`'s own applies (both cycles were fully
  torn down); `bootstrap/` itself is still live. There is still no
  disposable sandbox project or automated teardown wired into CI — every
  real apply/destroy cycle so far has been run and verified by hand.
- **GitHub Actions pipelines**: `.github/workflows/*.yml` has still never
  actually triggered a run. The repo now has a real GitHub remote
  (`github.com/Prem-G01/terraform-gcp-framework`) and `bootstrap/`'s real
  WIF trust chain exists, but the two remaining GitHub-side steps
  (`ENVIRONMENTS_JSON` repository variable, GitHub Environments with
  required reviewers) are still manual and not yet done — see
  [docs/cicd.md](cicd.md) "One-time setup".
- **Most of `modules/`** still has no dedicated `.tftest.hcl` —
  `cloudsql`, `workload_identity`, `buckets`, `vm`, `kms`, and `secrets`
  do, plus `platform/tests/count_gating.tftest.hcl`'s coverage of
  `buckets`, `org_policies`, `iap`, and `binary_authorization`. The real
  `terraform plan`/`apply` against the real dev config (see above) is the
  only cross-module exercise the other ~23 types have had.
- **`org_policies`, `iap`, `workload_identity`, and
  `binary_authorization`** (added for the zero-trust workstream — see
  [docs/security.md](security.md)) have never been applied against a
  real project. `binary_authorization`'s `ALWAYS_DENY` default in
  particular has never been proven to actually block a real image
  deploy, only planned.
