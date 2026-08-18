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
  Neither `cicd/cloudbuild-plan.yaml` nor `cloudbuild-apply.yaml` pass
  `--force-security` — a real override in CI would need its own deliberate
  decision, not a default in the pipeline.

See `tests/test_override.py` for the enforcement (forces a security-only
violation through with an audit record; refuses when a non-security error
is also present; refuses without `--reason`).

## Cost validation — an honest limitation

`engine/cost_engine.py` estimates monthly spend from a **static**
USD/hour table in `config/global/cost.yaml` for VM machine types and Cloud
SQL tiers — not a Cloud Billing Catalog API call. There is no live pricing
lookup anywhere in this engine. Treat its `COST_THRESHOLD_EXCEEDED`
warning as a rough guardrail, not a forecast. A real integration would call
`cloudbilling.googleapis.com`'s Catalog API per SKU, which needs network
access and billing-account read permission the validation engine
deliberately doesn't have (it makes zero GCP API calls, by design — that's
what makes `pytest tests/` run in under a second with no credentials).

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
