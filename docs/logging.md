# Logging & artifacts

## What goes where

| What | Where | Retention |
|---|---|---|
| Terraform state | `gs://<state bucket>/<env>/` (GCS backend, versioned) | see `state_bucket_retention_days` in `bootstrap/variables.tf`, default 90 days of noncurrent versions + 7-day soft-delete |
| GitHub Actions run logs | GitHub's own Actions run history (`.github/workflows/*.yml`) | governed by the repository's Actions log-retention setting, not this repo's code |
| `validation.json`, `plan.txt`, `plan.json`, `apply_outputs.json` | `gs://<artifact bucket>/deployments/<env>/<run id>/` | 180-day lifecycle rule (`bootstrap/main.tf` `google_storage_bucket.artifacts`) |
| GCP audit logs (who ran what) | Cloud Audit Logs, automatic for every API call the `tf-plan-<env>`/`tf-apply-<env>` SAs make | governed by each project's org policy, not this repo |
| Application logs (from deployed workloads), per-environment copy | `modules/monitoring/logging` → `google_logging_project_bucket_config`, configured per-environment in `deployment.yaml` `resources.logging.instances` (dev has `app-logs` @ 30 days, `audit-logs` @ 365 days) | set per-instance in `deployment.yaml` |
| Every environment's exported logs, centralized copy | `gs://<log bucket>/` in the central project (`bootstrap/main.tf` `google_storage_bucket.logs`) — see "Centralized logging" below | `log_bucket_retention_days` in `bootstrap/variables.tf`, default 400 days |

Nothing above lives in git. `.gitignore` explicitly excludes `*.tfstate*`,
`**/.generated/`, `**/plan.txt`, `**/plan.json`, `**/validation.json`,
`**/deployment.json`, and `artifacts/` for exactly this reason.

## Centralized logging

Each environment's per-project log bucket (the row above) is where its
own `deployment.yaml`-configured retention applies, and it's what
disappears if that project is ever torn down. The central log bucket is
the durable copy, in the central project, outside the reach of anyone
whose access is scoped to just one spoke project:

- **`var.home_environment`** (default `dev`, whose real project IS the
  central project) gets its `google_logging_project_sink` created
  directly in `bootstrap/main.tf`, in the same apply as the bucket — no
  cross-project step needed.
- **Every other environment** gets its sink from `bootstrap/grants/`
  instead (see [docs/service-accounts.md](service-accounts.md)
  "Cross-project access") — that stack runs against the spoke project
  directly, since only someone with permissions there can create a sink
  in it. The sink's `writer_identity` output is only known after that
  apply; feed it back into bootstrap's `var.log_sink_writer_identities`
  (a `map(environment => writer_identity)`) and re-apply `bootstrap/` to
  grant that identity write access to the central bucket. Two applies,
  not one, because no single identity in this design has both
  "create a sink in the spoke project" and "grant bucket access in the
  central project" permissions at once — that's a deliberate boundary,
  not an oversight.

## What never gets logged

`engine/errors.Finding.render()` and every `engine/*.py` check operate
purely on `deployment.yaml` structure (field names, booleans, resource
type names) — never on `random_password` results, `google_secret_manager
_secret_version` payloads, or any other credential material. GitHub
Actions' step logs will show Terraform's own output, which is why Cloud
SQL user passwords are wired via `var.passwords[...]` sourced from
`module.secrets.passwords` (marked `sensitive = true` in
`modules/security/secrets/outputs.tf`) rather than ever appearing as a
plain resource attribute in a YAML file or CLI argument.

## Bucket names are not hardcoded

`bootstrap/variables.tf state_bucket_name` / `artifact_bucket_name` /
`log_bucket_name` have no default — bucket names are globally unique
across all of GCP, so a template default would either collide or
encourage copy-pasting a name that isn't actually yours. Choose them
deliberately at `bootstrap apply` time (see
[docs/state-management.md](state-management.md)).
