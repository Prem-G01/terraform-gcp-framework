# Architecture

## The pipeline

```
config/environments/<env>/deployment.yaml   (single source of truth per env)
config/global/*.yaml                        (org-wide policy — never overridden per-env)
        │
        ▼
engine/config_loader.py     — YAML syntax + deep-merge resource_defaults + required labels
engine/schema_validator.py  — JSON Schema (envelope, known types) + required-field rules
engine/dependency_engine.py — type-level "does X require Y" + instance cross-references
engine/security_engine.py   — public SSH/RDP, public VM/bucket/SQL, missing OS Login /
                               Shielded VM, overprivileged SA, KMS rotation, secret length
engine/naming_engine.py     — pattern/length/reserved-word checks
engine/region_engine.py     — region/zone allow-list
engine/cost_engine.py       — static list-price threshold warning (NOT live billing)
        │
        ▼ (only if nothing ERROR-severity)
engine/cli.py render        — writes environments/<env>/.generated/deployment.normalized.json
        │
        ▼
platform/  (Terraform)      — one `module` block per resource type, `count`-gated
        │
        ▼
environments/<env>/         — ~10-line stack: backend + provider + `module "platform"`
```

Terraform never reads `config/environments/<env>/deployment.yaml` directly —
only the rendered, already-validated JSON. That's the actual mechanism that
stops an invalid config from reaching `terraform apply`: `render` refuses to
write the file, so `terraform plan` fails on a missing file (see
[docs/validation.md](validation.md)).

## Why one `platform/` module instead of duplicated per-environment Terraform

Every environment's `environments/<env>/main.tf` is the same ~10 lines:

```hcl
module "platform" {
  source          = "../../platform"
  project_id      = var.project_id
  environment     = var.environment
  deployment_file = "${path.module}/.generated/deployment.normalized.json"
}
```

All resource logic lives once, in `platform/main.tf`. `platform/` has no
`if environment == "prod"` branching anywhere — every difference between
dev and prod is a difference in `deployment.yaml` data, never in code. See
`environments/dev`, `environments/sit`, `environments/uat`,
`environments/prod` — they're structurally identical.

## Why not fully dynamic resource kinds

The spec that drove this rebuild asked for the platform to "determine which
resources to deploy based on YAML" without a fixed module list. That's true
at the *instance* level — `resources.vm.instances` can have any number of
VMs, no HCL change needed — but Terraform's graph is resolved statically at
`terraform init`/`plan` time, so it cannot loop over an arbitrary *resource
type* named in a data file the way it loops over instances of a known type.
Two ways to get closer to true dynamism exist and were deliberately not
taken:

- **A code generator** that emits `platform/main.tf` from
  `config/schema/deployment.schema.json` before every plan. Rejected: it
  turns "read the Terraform" into "read the generator that reads the
  schema that generates the Terraform," and a generated-file diff is much
  harder to review in a PR than a hand-written one for a bounded, slowly-
  changing list of ~33 GCP resource types.
- **A single generic `google_*_resource` style escape hatch** (e.g. driving
  the `google-beta` dynamic resource support). Rejected: it defeats
  `terraform plan` readability and the security/naming/dependency engines,
  which all know the shape of specific resource types.

So `platform/main.tf` has one `module` block per resource type — a bounded,
explicit registry — each gated by `count = local.enabled.<type> ? 1 : 0`.
Adding a genuinely new resource *type* is a `platform/` + `modules/` change
(see [docs/modules.md](modules.md)); adding a new *instance* of an existing
type is a pure `deployment.yaml` change.

## State boundaries

Deliberately **not** split into per-layer state (foundation/network/
security/compute/data/application/observability) in this rebuild — see
[docs/state-management.md](state-management.md) "Why one state file per
environment for now" for the reasoning and what splitting it later would
require.
