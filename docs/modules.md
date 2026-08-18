# Modules

## Contract every module follows

```hcl
variable "project_id" { type = string }
variable "config"     { type = any }     # { <plural_key> = <map of instances> }
# + whatever cross-module inputs it needs (vpcs, subnets, service_accounts, ...)
```

`for_each` inside the module iterates `var.config.<plural_key>` — a map
keyed by the instance name from `deployment.yaml`. A resource's GCP `name`
falls back to that map key when the instance doesn't set one explicitly:
`name = lookup(each.value, "name", each.key)`. Explicit `name` stays
available for the few resources that need one different from the
engineer-facing key — bucket names, which must be globally unique across
all of GCP, are the main example (see `config/environments/dev/
deployment.yaml` `resources.buckets`).

Modules are environment-agnostic by construction — nothing under
`modules/` references `"dev"`, a project ID, or a region literal (enforced
by `engine/hardcode_scanner.py`, which scans exactly this directory; see
`tests/test_hardcode_scanner.py::test_real_modules_have_no_hardcoded
_project_ids_or_cidrs`).

## Where defaults actually get applied

`config/global/defaults.yaml` `resource_defaults` is merged into each
instance **once**, in Python (`engine/config_loader.deep_merge`), before
Terraform ever runs — not re-implemented in HCL. `platform/main.tf`'s
`module "vm" { config = { vms = local.instances.vm } }` passes the
already-merged instance straight through. This is a deliberate DRY
decision: the alternative (defaults merged again inside each Terraform
module via a wall of `lookup(each.value, "field", var.defaults.field)`
calls) would duplicate the same logic in two languages and the two could
drift.

## Directory layout

```
modules/
  shared/{labels,tags,naming}          trivial pass-through + naming-pattern outputs
  apis/                                  google_project_service
  networking/{vpc,subnet,firewall,router,nat,private_service_access,load_balancer}
  iam/service_accounts/
  compute/{vm,cloudrun}
  database/cloudsql/                    includes google_sql_user — see below
  storage/buckets/
  artifact_registry/
  security/{kms,secrets}
  messaging/{pubsub,cloudtasks}
  orchestration/{scheduler,workflows}
  monitoring/{notification_channels,alert_policies,uptime_checks,logging}
  analytics/bigquery/
  ai/documentai/
  compute/gke/                           private-by-construction: workload identity,
                                          network policy, and shielded nodes are not
                                          config toggles — always on
  compute/cloudfunctions/                2nd-gen; source is a pre-uploaded bucket
                                          object, not zipped by this module
  database/memorystore/                  Redis, Private Service Access only, no
                                          public-IP mode exposed at all
  security/vpc_service_controls/         org-level singleton policy — see
                                          docs/security.md before enabling
```

## Alert policy aligners

`modules/monitoring/alert_policies` lets each instance set its own
`aligner` (Cloud Monitoring `per_series_aligner`), defaulting to
`ALIGN_MEAN` — but the right aligner depends entirely on the metric's
**kind**, and picking wrong either fails at apply time or, worse, creates
a policy that silently never fires:

| Metric kind | Example | Correct aligner |
|---|---|---|
| GAUGE (a ratio/level, e.g. CPU or memory utilization) | `compute.googleapis.com/instance/cpu/utilization`, `redis.googleapis.com/stats/memory/usage_ratio` | `ALIGN_MEAN` (the default) |
| CUMULATIVE (a counter that only increases, e.g. request/execution count) | `cloudfunctions.googleapis.com/function/execution_count` | `ALIGN_RATE` (converts to a per-second rate) or `ALIGN_DELTA` |
| BOOL (a condition that's true/false) | `kubernetes.io/node/status_condition` | `ALIGN_FRACTION_TRUE` or `ALIGN_COUNT_TRUE` |

Before adding a new alert, check the metric's kind in Cloud Monitoring's
Metrics Explorer (or `gcloud monitoring metrics-descriptors describe
<type>`) — don't assume. `config/environments/dev/deployment.yaml`
deliberately does **not** include a GKE "node not ready" alert on
`kubernetes.io/node/status_condition` — its exact label schema wasn't
verified against a real cluster in this session, and shipping an
unverified filter would be false monitoring coverage. Verify it for real,
then add it.

## Bug fixed in this rebuild: Cloud SQL users were never created

The original `modules/database/cloudsql/main.tf` computed a
`local.sql_users` list (instance/username/secret mapping) from
`deployment.yaml` but had no `google_sql_user` resource consuming it — the
Cloud SQL *instance* and the Secret Manager *passwords* were created, but
the actual database user accounts never were. Fixed by adding:

```hcl
resource "google_sql_user" "users" {
  for_each = local.sql_users_map
  project  = var.project_id
  instance = google_sql_database_instance.cloudsql[each.value.instance_name].name
  name     = each.value.username
  host     = each.value.host
  password = var.passwords[each.value.secret_name]
}
```

## Adding a new module (a genuinely new resource type)

1. Write `modules/<category>/<name>/{main,variables,outputs}.tf` following
   the contract above.
2. Add the type to `config/schema/deployment.schema.json`
   `resources.properties`.
3. Add its required fields to `RESOURCE_RULES` in
   `engine/schema_validator.py` (optional but recommended).
4. Add it to `local.resource_types` in `platform/locals.tf`.
5. Add a `count`-gated `module` block in `platform/main.tf`, following the
   existing pattern (`count = local.enabled.<type> ? 1 : 0`).
6. If it depends on another type, add an entry to
   `config/global/dependencies.yaml`.
7. Add an example instance to `config/environments/dev/deployment.yaml`
   and run `python -m engine.cli validate config/environments/dev`.

## Adding a new instance of an existing type

Pure `deployment.yaml` change — no Terraform, no Python. See
[docs/configuration.md](configuration.md).
