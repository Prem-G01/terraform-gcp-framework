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

`bootstrap/` creates the state bucket, artifact bucket, and CI/CD service
accounts. It cannot itself use a GCS backend — the bucket doesn't exist
yet — so it deliberately uses `backend "local"` (see `bootstrap/versions.tf`).
Run it once, manually, by a human with org-level IAM permissions:

```bash
cd bootstrap
terraform init
terraform apply \
  -var project_id=prj-dg-devops-test \
  -var state_bucket_name=<choose a globally-unique name> \
  -var artifact_bucket_name=<choose a globally-unique name>
```

**This has been run**, against `prj-dg-devops-test`, on 2026-08-18 — see
[docs/troubleshooting.md](troubleshooting.md) "Bootstrap is now live" for
what happened (including a real `terraform import` incident worth reading
before you run this again for another project). Outputs, for this project:

| Output | Value |
|---|---|
| `state_bucket` | `prj-dg-devops-test-tfstate` |
| `artifact_bucket` | `prj-dg-devops-test-tf-artifacts` |
| `terraform_plan_sa_email` | `tf-plan@prj-dg-devops-test.iam.gserviceaccount.com` |
| `terraform_apply_sa_email` | `tf-apply@prj-dg-devops-test.iam.gserviceaccount.com` |

These are the values every environment's `terraform init -backend-config=`
and Cloud Build trigger `substitutions` need.

**Still pending**: `bootstrap/terraform.tfstate.bootstrap` (local) should
be copied into the new state bucket as a backup —
`gs://prj-dg-devops-test-tfstate/bootstrap/terraform.tfstate` — but the
`gsutil cp` attempt failed with `Reauthentication required.` and needs an
interactive `gcloud auth login` (see
[docs/troubleshooting.md](troubleshooting.md) "Bootstrap is now live").
`bootstrap/versions.tf` itself still points at local state regardless —
reconfiguring it to a `gcs` backend pointed at that path is a further,
deliberate follow-up step.

## Why one state file per environment for now

The spec this rebuild followed asked for layer-based state separation
(foundation/network/security/compute/data/application/observability).
That's not implemented — each environment is one Terraform state, produced
by one `platform/` module invocation. Two honest reasons:

1. **Blast radius vs. operational cost.** This platform's dev footprint is
   ~80 resources across 25 types. Splitting that into 7 states means 7
   `terraform init`s, 7 sets of cross-state `terraform_remote_state` data
   sources, and 7 places a plan can go stale relative to its dependencies
   — a real cost that only pays for itself once a single state's blast
   radius or plan time becomes a genuine operational problem.
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
