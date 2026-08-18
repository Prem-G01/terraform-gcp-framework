# Logging & artifacts

## What goes where

| What | Where | Retention |
|---|---|---|
| Terraform state | `gs://<state bucket>/<env>/` (GCS backend, versioned) | see `state_bucket_retention_days` in `bootstrap/variables.tf`, default 90 days of noncurrent versions + 7-day soft-delete |
| Cloud Build step logs | Cloud Logging (`options.logging: CLOUD_LOGGING_ONLY` in both `cicd/*.yaml`) | governed by the project's Cloud Logging retention, not this repo |
| `validation.json`, `plan.txt`, `plan.json`, `apply_outputs.json` | `gs://<artifact bucket>/deployments/<env>/<build id>/` | 180-day lifecycle rule (`bootstrap/main.tf` `google_storage_bucket.artifacts`) |
| GCP audit logs (who ran what) | Cloud Audit Logs, automatic for every API call the `tf-plan`/`tf-apply` SAs make | governed by the project's org policy, not this repo |
| Application logs (from deployed workloads) | `modules/monitoring/logging` → `google_logging_project_bucket_config`, configured per-environment in `deployment.yaml` `resources.logging.instances` (dev has `app-logs` @ 30 days, `audit-logs` @ 365 days) | set per-instance in `deployment.yaml` |

Nothing above lives in git. `.gitignore` explicitly excludes `*.tfstate*`,
`**/.generated/`, `**/plan.txt`, `**/plan.json`, `**/validation.json`,
`**/deployment.json`, and `artifacts/` for exactly this reason.

## What never gets logged

`engine/errors.Finding.render()` and every `engine/*.py` check operate
purely on `deployment.yaml` structure (field names, booleans, resource
type names) — never on `random_password` results, `google_secret_manager
_secret_version` payloads, or any other credential material. Cloud Build's
step logs will show Terraform's own output, which is why Cloud SQL user
passwords are wired via `var.passwords[...]` sourced from `module.secrets
.passwords` (marked `sensitive = true` in
`modules/security/secrets/outputs.tf`) rather than ever appearing as a
plain resource attribute in a YAML file or CLI argument.

## Bucket names are not hardcoded

`bootstrap/variables.tf state_bucket_name` / `artifact_bucket_name` have no
default — bucket names are globally unique across all of GCP, so a
template default would either collide or encourage copy-pasting a name
that isn't actually yours. Choose them deliberately at `bootstrap apply`
time (see [docs/state-management.md](state-management.md)).
