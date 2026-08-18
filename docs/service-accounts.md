# Service-account model

## One dedicated plan/apply pair per environment

`bootstrap/main.tf` creates a **separate** `tf-plan-<env>`/`tf-apply-<env>`
pair for every entry in `var.environments` (`dev`, `sit`, `uat`, `prod` by
default) — not one shared pair for all of them. A compromised or
misconfigured `dev` deploy identity can never touch `sit`/`uat`/`prod`;
that containment is the whole point. All pairs are hosted in the same
project (`var.project_id`, the "central" project) regardless of where
each environment's actual GCP resources live — see "Cross-project access"
below.

A bootstrap-specific and a validation-specific SA (the other two of the
spec's four identities) still don't exist — bootstrap is a rare, manual,
human-run operation (see [docs/state-management.md](state-management.md)),
and validation (`engine/`) makes zero GCP API calls, so it needs no
identity of its own — it runs as whatever identity happens to invoke
`python -m engine.cli`, with no IAM footprint.

| Service account | Roles (see `modules/iam/deploy_roles`) | Used by |
|---|---|---|
| `tf-plan-<env>@<central project>` | `roles/viewer`, `roles/iam.securityReviewer` — read-only | `.github/workflows/plan.yml`, every PR |
| `tf-apply-<env>@<central project>` | Curated per-service `*.admin` roles matching exactly what `modules/` creates (compute, storage, Cloud SQL, Secret Manager, KMS, Cloud Run, Pub/Sub, Cloud Tasks, Scheduler, Workflows, Artifact Registry, Monitoring, Logging, BigQuery) + `serviceAccountAdmin`/`serviceAccountUser`/`projectIamAdmin`/`serviceUsageAdmin` | `.github/workflows/apply.yml`, only after the target GitHub Environment's required reviewer approves |

Deliberately **not** `roles/editor` or `roles/owner` — see
`config/global/security.yaml` `SEC_OVERPRIVILEGED_SERVICE_ACCOUNT`, which
exists specifically to catch that pattern in resources this platform
creates. Tighten `modules/iam/deploy_roles` further if your org's policy
requires custom roles instead of predefined `*.admin` ones — both
`bootstrap/main.tf` and `bootstrap/grants/main.tf` read from that one
module, so there's a single list to change, not two that can drift apart.

The state and artifact buckets are shared (every environment's state
lives in the same bucket, under `-backend-config="prefix=<env>"`), but
each environment's SA can only reach its own prefix — enforced with a GCS
IAM condition (`resource.name.startsWith(".../objects/<env>/")`) on every
bucket binding, not just documented convention.

## Cross-project access

`sit`/`uat`/`prod` are configured as **separate GCP projects**
(`config/environments/{sit,uat,prod}/deployment.yaml` `project.id`), but
their `tf-plan`/`tf-apply` identities live centrally in
`var.project_id` (typically the same project as `dev`, via
`var.home_environment`, default `"dev"`). `bootstrap/main.tf` can only
grant IAM roles inside its own project — it has no credentials for
`sit`/`uat`/`prod`'s projects, and shouldn't need any (concentrating
IAM-admin power over every spoke project into one bootstrap run is a
bigger blast radius than the identity separation above is trying to
avoid).

Instead, **`bootstrap/grants/`** is a small, separate Terraform stack —
applied once per spoke project, by whoever actually owns IAM there — that
grants the already-existing `tf-plan-<env>`/`tf-apply-<env>` (created
centrally by `bootstrap/`) the same curated roles, but scoped to that
project:

```bash
cd bootstrap/grants
terraform init
terraform apply \
  -var spoke_project_id=<sit/uat/prod project id> \
  -var central_project_id=<bootstrap's var.project_id> \
  -var environment=sit \
  -var region=<that environment's region> \
  -var central_log_bucket=<bootstrap's log_bucket output>
```

Identity is created once, centrally; permissions are granted locally, by
whoever is actually accountable for that project — the same separation of
concerns as `roles/iam.serviceAccountAdmin` (who an identity is) versus
`roles/resourcemanager.projectIamAdmin` (what it can do where).

## No long-lived keys

`bootstrap/main.tf` provisions Workload Identity Federation
(`google_iam_workload_identity_pool` + `..._provider`) behind
`var.enable_workload_identity_federation` (default `false`). When enabled
with `github_repository = "<org>/<repo>"`, GitHub Actions can assume any
environment's `tf-plan-<env>`/`tf-apply-<env>` — no JSON key ever created
or stored, see `.github/workflows/plan.yml` and `apply.yml`. The apply
bindings go further: `tf-apply-<env>` can only be assumed by a token whose
`attribute.environment` claim equals `<env>`, and GitHub only stamps that
claim onto a job's OIDC token once that job is actually running under the
matching GitHub Environment — i.e. once its required reviewers have
approved. `tf-apply-prod` cannot be assumed by a workflow run that hasn't
been approved for `prod`, even from the right repository.

## Central repository: GitHub, not GCP-hosted

This platform's git remote is GitHub — `.github/workflows/*.yml` are
triggered by pushes/PRs to it, and authenticate to GCP via the Workload
Identity Federation pool above. An earlier iteration briefly provisioned
a Secure Source Manager (GCP-hosted git) instance/repository instead;
that was reverted (see [docs/troubleshooting.md](troubleshooting.md))
once the decision was made to keep the repo on GitHub with GitHub Actions
as the CI/CD engine. Nothing in `modules/` or `platform/` depends on
where the repo lives, so this was a CI/CD-layer choice only.

## What this rebuild did not do

- WIF is authored but **not applied** — creating a real pool/provider and
  wiring it to an actual CI system requires knowing the real repository
  and having org-level IAM permissions, both explicitly out of scope for
  this code-only rebuild (see [docs/troubleshooting.md](troubleshooting.md)).
  Run `terraform apply` in `bootstrap/` with
  `enable_workload_identity_federation = true` and a real
  `github_repository` value (`"<org>/<repo>"`) when you're ready to wire
  this up for real.
- `bootstrap/grants/` has never been applied against a real `sit`/`uat`/
  `prod` project — those are still placeholder project IDs in
  `config/environments/{sit,uat,prod}/deployment.yaml`.
