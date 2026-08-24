# State management

## Remote state

Every `environments/<env>/versions.tf` declares `backend "gcs" {}` with no
bucket name in the file (a bucket name is exactly the kind of
environment-specific literal the zero-hardcode policy exists to keep out of
committed HCL — see `engine/hardcode_scanner.py`). It's supplied at
`terraform init` time:

```bash
terraform init \
  -backend-config="bucket=<state bucket from bootstrap output>" \
  -backend-config="prefix=dev"
```

For this project that bucket is real: `prj-dg-devops-test-tfstate` (see
"Bootstrapping" below).

GCS backends get state locking, versioning, and consistency for free once
the bucket itself has object versioning on — which `bootstrap/main.tf`
enables, along with uniform bucket-level access, enforced public-access
prevention, and a lifecycle rule that prunes noncurrent versions after
`var.state_bucket_retention_days` (default 90). `google_storage_bucket
.state`'s `soft_delete_policy` adds a further 7-day undelete window on top
of that.

## Bootstrapping

`bootstrap/` creates the state bucket, artifact bucket, central log
bucket, and one dedicated `tf-plan-<env>`/`tf-apply-<env>` pair per
environment. It cannot itself use a GCS backend — the bucket doesn't
exist yet — so it deliberately uses `backend "local"` (see
`bootstrap/versions.tf`). Run it once, manually, by a human with
org-level IAM permissions:

```bash
cd bootstrap
terraform init
terraform apply \
  -var project_id=prj-dg-devops-test \
  -var state_bucket_name=<choose a globally-unique name> \
  -var artifact_bucket_name=<choose a globally-unique name> \
  -var log_bucket_name=<choose a globally-unique name>
```

This only grants project-level roles for `var.home_environment` (default
`dev`, whose real GCP project is `var.project_id`) — `sit`/`uat`/`prod`
(separate projects) each need `bootstrap/grants/` applied once against
their own project afterward, see
[docs/service-accounts.md](service-accounts.md) "Cross-project access".

**A previous version of this was run**, against `prj-dg-devops-test`, on
2026-08-18, with a single shared `tf-plan`/`tf-apply` pair — see
[docs/troubleshooting.md](troubleshooting.md) "Bootstrap is now live" for
what happened (including a real `terraform import` incident worth reading
before you run this again for another project). That deployment was fully
torn down the same day, and `bootstrap/main.tf` was rewritten to the
per-environment design described above.

**The current design was applied for real**, against `prj-dg-devops-test`,
on 2026-08-19 — 56 resources, real outputs below. See
[docs/troubleshooting.md](troubleshooting.md) "Bootstrap re-applied" for
a real bucket-name-collision incident hit partway through (unrelated to
this repo — a different, real "audit-platform" project had claimed
`prj-dg-devops-test-tfstate` in this same shared test project since the
previous day).

| Output | Value |
|---|---|
| `state_bucket` | `prj-dg-devops-test-tfstate-v2` (not `-tfstate` — see the incident above) |
| `artifact_bucket` | `prj-dg-devops-test-tf-artifacts` |
| `log_bucket` | `prj-dg-devops-test-logs` |
| `terraform_plan_sa_emails` | `tf-plan-<env>@prj-dg-devops-test.iam.gserviceaccount.com` for `dev`/`sit`/`uat`/`prod` |
| `terraform_apply_sa_emails` | `tf-apply-<env>@prj-dg-devops-test.iam.gserviceaccount.com` for `dev`/`sit`/`uat`/`prod` |

These are the values every environment's `terraform init -backend-config=`
and `.github/workflows/*.yml` `ENVIRONMENTS_JSON` repository variable need
(see [docs/cicd.md](cicd.md)). Only `dev` (this apply's `var.home_environment`)
has its `tf-apply`/`tf-plan` roles actually granted so far —
`sit`/`uat`/`prod`'s pairs exist as identities but have no roles anywhere
yet, pending `bootstrap/grants/` against their real (still placeholder)
project IDs.

`bootstrap/terraform.tfstate.bootstrap` (local) was copied to
`gs://prj-dg-devops-test-tfstate-v2/bootstrap/terraform.tfstate` as a
backup immediately after this apply. `bootstrap/versions.tf` itself
stays on `backend "local"` regardless — reconfiguring it to a `gcs`
backend pointed at that path is
still a deliberate, separate follow-up step whenever you next run this for
real.

## Why one state file per environment for now

The spec this rebuild followed asked for layer-based state separation
(foundation/network/security/compute/data/application/observability).
That's not implemented — each environment is one Terraform state, produced
by one `platform/` module invocation. Two honest reasons:

1. **Blast radius vs. operational cost.** This platform's dev footprint
   has every resource type enabled except the deliberately-off
   `vpc_service_controls` (32 of 33). Splitting that into 7 states means
   7 `terraform init`s, 7 sets of cross-state `terraform_remote_state`
   data sources, and 7 places a plan can go stale relative to its
   dependencies — a real cost that only pays for itself once a single
   state's blast radius or plan time becomes a genuine operational
   problem.
2. **This rebuild was not applied against real infrastructure**, so there
   was no live state to observe actually being slow or risky to plan as
   one unit — splitting preemptively, without that evidence, is exactly
   the kind of premature abstraction this rebuild's own "do not
   overengineer" principle argues against (see `docs/architecture.md` and
   the rebuild's guiding principles).

**If you do need to split it later**, the natural boundary is exactly the
`platform/main.tf` module list: pull `vpc`/`subnet`/`firewall`/`router`/
`nat`/`private_service_access` into a `platform-network/` module, keep
compute/data/application in `platform/`, and connect them with
`data "terraform_remote_state" "network" { backend = "gcs"; config = {
bucket = ..., prefix = "dev/network" } }` instead of the current
`try(module.vpc[0].self_links, {})` in-process references. Every
cross-module reference in `platform/main.tf` is already isolated to a
handful of `try(module.x[0].output, {})` lines — that's exactly where a
future split would replace an in-process reference with a remote-state
lookup.
