# Service-account model

## Four identities, least privilege

`bootstrap/main.tf` creates exactly two of the four the spec calls for —
**plan** and **apply** — because a bootstrap-specific and a
validation-specific SA add operational overhead without a corresponding
security benefit here: bootstrap is a rare, manual, human-run operation
(see [docs/state-management.md](state-management.md)), and validation
(`engine/`) makes zero GCP API calls, so it needs no identity of its own —
it runs as whatever identity happens to invoke `python -m engine.cli`,
with no IAM footprint.

| Service account | Roles (see `bootstrap/main.tf` locals) | Used by |
|---|---|---|
| `tf-plan@<project>` | `roles/viewer`, `roles/iam.securityReviewer` — read-only | `cicd/cloudbuild-plan.yaml`, every PR |
| `tf-apply@<project>` | Curated per-service `*.admin` roles matching exactly what `modules/` creates (compute, storage, Cloud SQL, Secret Manager, KMS, Cloud Run, Pub/Sub, Cloud Tasks, Scheduler, Workflows, Artifact Registry, Monitoring, Logging, BigQuery) + `serviceAccountAdmin`/`serviceAccountUser`/`projectIamAdmin`/`serviceUsageAdmin` | `cicd/cloudbuild-apply.yaml`, only after trigger approval |

Deliberately **not** `roles/editor` or `roles/owner` — see
`config/global/security.yaml` `SEC_OVERPRIVILEGED_SERVICE_ACCOUNT`, which
exists specifically to catch that pattern in resources this platform
creates. Tighten the `apply_sa_roles` list in `bootstrap/main.tf` further
if your org's policy requires custom roles instead of predefined `*.admin`
ones.

## No long-lived keys

`bootstrap/main.tf` provisions Workload Identity Federation
(`google_iam_workload_identity_pool` + `..._provider`) behind
`var.enable_workload_identity_federation` (default `false`). When enabled
with `github_repository = "<org>/<repo>"`, GitHub Actions (or any OIDC-
capable CI) can assume `tf-plan`/`tf-apply` via
`principalSet://iam.googleapis.com/<pool>/attribute.repository/<org>/<repo>`
— no JSON key ever created or stored. Cloud Build running in the same GCP
project can instead run directly as these service accounts via
`--service-account` on the trigger (see `cicd/cloudbuild-plan.yaml`
header), which also needs no key.

## Central repository: GitHub, not GCP-hosted

This platform's git remote is GitHub — `cicd/` pipelines are triggered by
GitHub Actions, which authenticates to GCP via the Workload Identity
Federation pool below. An earlier iteration briefly provisioned a Secure
Source Manager (GCP-hosted git) instance/repository instead; that was
reverted (see [docs/troubleshooting.md](troubleshooting.md)) once the
decision was made to keep the repo on GitHub. Nothing in `modules/` or
`platform/` depends on where the repo lives, so this is a CI/CD-layer
choice only.

## What this rebuild did not do

WIF is authored but **not applied** — creating a real pool/provider and
wiring it to an actual CI system requires knowing the real repository and
having org-level IAM permissions, both explicitly out of scope for this
code-only rebuild (see
[docs/troubleshooting.md](troubleshooting.md)). Run
`terraform apply` in `bootstrap/` with `enable_workload_identity_federation
= true` and a real `github_repository` value (`"<org>/<repo>"`) when
you're ready to wire this up for real — GitHub Actions can then assume
`tf-plan`/`tf-apply` via
`principalSet://iam.googleapis.com/<pool>/attribute.repository/<org>/<repo>`,
with no service-account key ever created or stored.
