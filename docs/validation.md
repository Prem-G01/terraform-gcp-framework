# Validation engine

## Pipeline

`python -m engine.cli validate config/environments/<env>` runs, in order:

1. **YAML syntax** — `engine/config_loader.py`, raises `ConfigError` on
   malformed YAML.
2. **Schema validation** — `engine/schema_validator.validate_schema`
   against `config/schema/deployment.schema.json`. Checks the envelope
   (`apiVersion`, `kind`, `metadata`, `project`, `region`), that every
   `resources.*` key is one of the 25 known types, and that each follows
   the `enabled` + `instances` shape. If this fails, nothing downstream
   runs — a malformed envelope makes every other check meaningless.
3. **Required fields** — `engine/schema_validator.validate_required_fields`
   against the `RESOURCE_RULES` table (dotted-path required fields per
   resource type, e.g. `vm` needs `zone`, `machine_type`, `subnet`,
   `service_account.name`, `boot_disk.image`).
4. **Dependency graph integrity** — `engine/dependency_engine
   .validate_dependency_graph_integrity` detects cycles in
   `config/global/dependencies.yaml` itself (config-level, not
   deployment-specific — also unit tested directly).
5. **Type-level dependencies** — is every `requires`d type also enabled?
6. **Instance references** — does `vm.app01.subnet: "x"` actually name an
   instance under `resources.subnet.instances`?
7. **Security** — `engine/security_engine.py`, rule conditions in code,
   severity from `config/global/security.yaml`.
8. **Naming** — pattern/length/reserved-word checks.
9. **Region** — allow-list checks.
10. **Cost** — static threshold warning (never blocks).

Exit code is 1 if anything ERROR-severity was found, 0 otherwise. `render`
(step after validate in the real pipeline) refuses to write the normalized
JSON Terraform reads if validation is blocked — see
[docs/architecture.md](architecture.md).

## Example: rejecting an invalid config

```bash
$ python -m engine.cli validate tests/fixtures/invalid_missing_network
VALIDATION FAILED

Resource:
  vm.test-vm

Rule:
  VM_NETWORK_REQUIRED

Error:
  Required field(s) missing for resource type 'vm'.

Missing:
  subnet
  service_account.name
  boot_disk.image

------------------------------------------------------------

VALIDATION FAILED

Resource:
  vm

Rule:
  VM_DEPENDENCY_MISSING

Error:
  'vm' requires subnet, service_accounts to be enabled, but subnet is not.
...
```

`tests/test_validation.py::test_vm_without_network_is_rejected` runs this
exact fixture and asserts both findings fire. `tests/fixtures/valid_minimal`
is the same scenario made correct (vpc + subnet + service_accounts all
enabled and referenced correctly) and is asserted to produce zero errors.

## Break-glass override — `--force-security`

Some situations are deliberate, known exceptions to policy — the clearest
real example: temporarily disabling `deletion_protection` on a Cloud SQL
instance specifically in order to tear it down (see
`docs/troubleshooting.md` "Dev was applied, then torn down"). `render`
supports exactly this, and nothing else:

```bash
python -m engine.cli render config/environments/dev \
  --out environments/dev/.generated/deployment.normalized.json \
  --force-security --reason "tearing down dev per user request 2026-08-18"
```

Rules:
- **Only SECURITY-category ERROR findings can be forced.** If the block
  includes any schema, dependency, naming, region, or YAML error, `render`
  refuses outright — those mean the config itself is broken, not that a
  policy exception is being made, and there is no override for that.
- **`--reason` is mandatory** — `render` errors before even validating if
  `--force-security` is set without it.
- **Every use is audited.** A JSON line is appended to
  `<out-dir>/override-audit.jsonl` — timestamp, OS user, reason, and every
  finding that was overridden. Nothing about this is silent, and it's not
  gitignored separately from the rest of `.generated/` on purpose — treat
  it as something to review, not hide.
- This is a CLI-level escape hatch for a human running `render` directly.
  Neither `.github/workflows/plan.yml` nor `apply.yml` pass
  `--force-security` — a real override in CI would need its own deliberate
  decision, not a default in the pipeline.

See `tests/test_override.py` for the enforcement (forces a security-only
violation through with an audit record; refuses when a non-security error
is also present; refuses without `--reason`).

## Secret scanning

`python -m engine.cli secret-scan .` — separate from `hardcode-scan`
(which looks for environment-specific *values* like project IDs that
belong in config, not code) and separate from the deployment validation
pipeline above (which only looks at `deployment.yaml`). This scans the
**whole repository** for content that looks like an actual leaked
credential:

- PEM private key blocks (`-----BEGIN ... PRIVATE KEY-----`)
- A GCP service-account JSON key's real shape — the `private_key` field's
  *value* starting with a PEM header, not just a field named `private_key`
- AWS access key IDs (`AKIA[0-9A-Z]{16}`)
- Slack tokens (`xox[baprs]-...`)

Deliberately high-confidence patterns only — no generic entropy-based
"looks secret-ish" heuristic. This repo has many legitimately-named fields
(`password_secret:`, `secret_id:`, `existing_access_policy_id:`) that
reference or describe a secret without containing one; a looser heuristic
would drown in false positives on exactly those. See
`engine/secret_scanner.py`'s own docstring, and the regression test
`tests/test_secret_scanner.py::test_scanner_does_not_flag_its_own_source`
— an earlier version of this scanner matched on the field name
`"private_key"` alone and flagged its own pattern-definition source code.

Same `# secret-allow: <reason>` suppression convention as
`hardcode_scanner.py`. Runs in both `.github/workflows/plan.yml` and
`apply.yml`, independently, so a secret introduced between a reviewed
plan and the later apply is still caught.

**If this ever finds something real**: treat the credential as
compromised the instant it's committed — rotate/revoke it — before
worrying about removing it from git history. Deleting the file doesn't
undo the leak; the old commit still has it.

## Cost validation — a static estimate, plus one deliberate live exception

`engine/cost_engine.py` (run automatically by `validate`/`render`,
including in CI) estimates monthly spend from a **static** USD/hour table
in `config/global/cost.yaml` for VM machine types and Cloud SQL tiers —
not a live API call. Treat its `COST_THRESHOLD_EXCEEDED` warning as a
rough guardrail, not a forecast. This stays static on purpose: the
validation engine makes zero GCP API calls by design, which is what
makes `pytest tests/` run in under a second with no credentials, and
every `validate`/`render` call in CI fast and independent of network
reachability.

**`python -m engine.cli cost-check-live <env-dir>`** (`engine/live_cost.py`)
is the one deliberate exception — a real Cloud Billing Catalog API call,
never run from `validate`/`render`/CI, needing its own separate
`pip install -r engine/requirements-live-cost.txt` and Application
Default Credentials (`gcloud auth application-default login`). Run it by
hand when you actually want current pricing, not on every plan. Honest
about its own limits rather than pretending to cover everything:

- Only Compute Engine `*-standard-N` shapes (`e2-standard-4`,
  `n2-standard-16`, ...) get a real live rate, computed from GCP's own
  per-region Core + RAM component SKUs (`vcpus × core_rate + (vcpus × 4
  GB) × ram_rate`) — verified against the real Catalog API for
  `asia-south1` while building this (an `e2-standard-2` there priced at
  $0.0805/hr live vs. $0.0720/hr in the static table, an ~12% gap; static
  tables drift, this is exactly the kind of thing a live check is for).
- Shared-core shapes (`e2-micro`, `e2-small`, `e2-medium`) and custom
  machine types fall back to the static table — their billing model
  (fractional vCPU billing) doesn't map onto the two-SKU formula above,
  and a wrong live number would be worse than an honestly-static one.
- Cloud SQL is static-only, full stop — its SKU shape is
  edition/tier-specific rather than a uniform core+RAM split, and wiring
  that up correctly was out of scope for this pass.
- It prices whatever shape you ask for, not whether GCP actually offers
  that exact size (`e2-standard-99` prices cleanly even though no such
  real machine type exists) — that's Compute Engine's problem at
  `terraform apply` time, not this tool's.

## Extending a rule

- New required field: add to `RESOURCE_RULES` in
  `engine/schema_validator.py`.
- New security rule: add an entry to `config/global/security.yaml` (id,
  applies_to, severity, description) **and** its condition to
  `engine/security_engine.validate_security` — the YAML entry alone only
  controls severity/description, not behavior (see
  `engine/security_engine.py`'s module docstring for why there's no
  generic policy DSL).
- New dependency: add to `config/global/dependencies.yaml` — no code
  change needed, `validate_type_dependencies` reads it directly.
