# CI/CD

## Pipeline

```
git push / PR
      │
      ▼
cicd/cloudbuild-plan.yaml   (tf-plan SA, read-only)
  validate → render → hardcode-scan + secret-scan → fmt-check → plan → upload plan.txt/plan.json/validation.json
      │
      ▼  (human reviews the plan in the PR / Cloud Build UI)
merge to main
      │
      ▼
cicd/cloudbuild-apply.yaml   (tf-apply SA — gated by the trigger's
                               --require-approval, a human must click
                               Approve in the Cloud Build console)
  validate → render → build-function-source + secret-scan → apply → upload apply_outputs.json/validation.json
```

`secret-scan` (see `docs/validation.md` "Secret scanning") runs in both
pipelines, independently — a secret introduced between the reviewed plan
and the later apply must still be caught, not just checked once.

`build-function-source` (see `docs/modules.md` "Building and uploading
Cloud Function source") zips and uploads every configured Cloud Function's
local source before `apply` runs, so Terraform always deploys the artifact
this same pipeline run just built — never a stale one left over from a
previous deploy.

No developer runs `terraform apply` from a laptop against a shared
environment — `environments/<env>/` works fine locally for `plan`
(read-only) but `apply` is deliberately something only the pipeline does,
as the `tf-apply` service account, after approval.

## One-time trigger setup

```bash
# Plan trigger — every PR
gcloud builds triggers create github \
  --name=tf-plan-dev \
  --repo-owner=<org> --repo-name=<repo> \
  --pull-request-pattern="^main$" \
  --build-config=cicd/cloudbuild-plan.yaml \
  --substitutions=_ENV=dev,_PROJECT_ID=prj-dg-devops-test,_STATE_BUCKET=<bootstrap output>,_ARTIFACT_BUCKET=<bootstrap output> \
  --service-account=projects/<project>/serviceAccounts/tf-plan@<project>.iam.gserviceaccount.com

# Apply trigger — merge to main, gated by manual approval
gcloud builds triggers create github \
  --name=tf-apply-dev \
  --repo-owner=<org> --repo-name=<repo> \
  --branch-pattern="^main$" \
  --build-config=cicd/cloudbuild-apply.yaml \
  --require-approval \
  --substitutions=_ENV=dev,_PROJECT_ID=prj-dg-devops-test,_STATE_BUCKET=<bootstrap output>,_ARTIFACT_BUCKET=<bootstrap output> \
  --service-account=projects/<project>/serviceAccounts/tf-apply@<project>.iam.gserviceaccount.com
```

Repeat per environment with `_ENV=sit|uat|prod` and each environment's own
project/bucket substitutions — the pipeline YAML itself never changes.

## Why re-validate in the apply pipeline

`cicd/cloudbuild-apply.yaml` re-runs `validate` + `render` from scratch
rather than trusting `cloudbuild-plan.yaml`'s artifacts. If `main` moved
between the plan a human approved and the apply actually running, the
apply pipeline validates the *current* `main`, not the approved snapshot —
an approval can never rubber-stamp a config that changed after review. If
you need strict plan-then-apply-of-that-exact-plan semantics instead,
download the plan artifact `cloudbuild-plan.yaml` uploaded to
`gs://<artifact bucket>/deployments/<env>/<build id>/plan.json` and pass it
to `terraform apply` directly instead of re-planning.

## What this rebuild did not do

No trigger, service account, or pipeline here has actually run — this
project has no connected git remote and this rebuild was explicitly
code-only (see [docs/troubleshooting.md](troubleshooting.md)). The YAML is
real and `terraform validate`/`fmt` were run against every stack it
orchestrates, but the Cloud Build steps themselves are untested against a
live build.
