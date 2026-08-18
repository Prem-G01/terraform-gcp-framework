# CI/CD

## Pipeline

```
git push / PR
      │
      ▼
.github/workflows/plan.yml   (tf-plan SA via WIF, read-only)
  validate → render → hardcode-scan + secret-scan → fmt-check → plan → upload plan.txt/plan.json/validation.json
      │
      ▼  (human reviews the plan in the PR)
merge to main
      │
      ▼
.github/workflows/apply.yml   (tf-apply SA via WIF — gated by the
                                matching GitHub Environment's required
                                reviewers, a human must click Approve)
  validate → render → build-function-source + secret-scan → apply → upload apply_outputs.json/validation.json
```

Both workflows authenticate to GCP via Workload Identity Federation
(`google_iam_workload_identity_pool_provider.github` in `bootstrap/main.tf`)
— no service-account key is ever created or stored in GitHub. Each
workflow first detects which environment(s) changed (from the diff, or a
`workflow_dispatch` input) and runs one matrix job per environment.

`secret-scan` (see `docs/validation.md` "Secret scanning") runs in both
workflows, independently — a secret introduced between the reviewed plan
and the later apply must still be caught, not just checked once.

`build-function-source` (see `docs/modules.md` "Building and uploading
Cloud Function source") zips and uploads every configured Cloud Function's
local source before `apply` runs, so Terraform always deploys the artifact
this same run just built — never a stale one left over from a previous
deploy.

No developer runs `terraform apply` from a laptop against a shared
environment — `environments/<env>/` works fine locally for `plan`
(read-only) but `apply` is deliberately something only `apply.yml` does,
as that environment's own `tf-apply-<env>` service account, after
approval. Every environment has its own dedicated `tf-plan-<env>`/
`tf-apply-<env>` pair (see
[docs/service-accounts.md](service-accounts.md)) — `dev`'s workflow run
can never authenticate as `prod`'s identity, even by mistake.

## One-time setup

1. **`bootstrap/`** — apply with `enable_workload_identity_federation =
   true` and `github_repository = "<org>/<repo>"`. This creates the WIF
   pool/provider and, for every environment, a dedicated `tf-plan-<env>`/
   `tf-apply-<env>` pair with the impersonation bindings letting only that
   repository (and, for apply, only a run under the matching GitHub
   Environment) assume them.

2. **`bootstrap/grants/`** — for every environment other than
   `var.home_environment` (typically `sit`, `uat`, `prod` — separate GCP
   projects), apply this once against that project so its
   `tf-plan-<env>`/`tf-apply-<env>` (created centrally by step 1) actually
   has roles there. See
   [docs/service-accounts.md](service-accounts.md) "Cross-project access".

3. **Repository variable `ENVIRONMENTS_JSON`** (Settings > Secrets and
   variables > Actions > Variables) — a JSON object keyed by environment
   name, values from the `bootstrap` outputs (`terraform_plan_sa_emails`/
   `terraform_apply_sa_emails` are already keyed by environment) plus the
   WIF provider resource name:

   ```json
   {
     "dev": {
       "wif_provider": "projects/<number>/locations/global/workloadIdentityPools/cicd-pool/providers/github",
       "tf_plan_sa": "tf-plan-dev@prj-dg-devops-test.iam.gserviceaccount.com",
       "tf_apply_sa": "tf-apply-dev@prj-dg-devops-test.iam.gserviceaccount.com",
       "state_bucket": "prj-dg-devops-test-tfstate",
       "artifact_bucket": "prj-dg-devops-test-tf-artifacts"
     },
     "sit": {
       "wif_provider": "projects/<number>/locations/global/workloadIdentityPools/cicd-pool/providers/github",
       "tf_plan_sa": "tf-plan-sit@prj-dg-devops-test.iam.gserviceaccount.com",
       "tf_apply_sa": "tf-apply-sit@prj-dg-devops-test.iam.gserviceaccount.com",
       "state_bucket": "prj-dg-devops-test-tfstate",
       "artifact_bucket": "prj-dg-devops-test-tf-artifacts"
     },
     "uat": { "...": "..." },
     "prod": { "...": "..." }
   }
   ```

   `wif_provider` and the bucket names are the same across every
   environment (one WIF pool, one central state/artifact bucket pair) —
   only `tf_plan_sa`/`tf_apply_sa` genuinely differ per environment. None
   of these values are secret (project IDs, bucket names, service account
   emails, and the WIF provider path are not credentials) — a repository
   *variable*, not a *secret*, is the correct GitHub construct here.

4. **GitHub Environments** — create `dev`, `sit`, `uat`, `prod` under
   Settings > Environments, and add required reviewers to each one you
   want gated (typically all but `dev`). `apply.yml` runs each matrix job
   under `environment: ${{ matrix.env }}`, so the job pauses for approval
   exactly there — this is the GitHub-native equivalent of Cloud Build's
   old `--require-approval` trigger flag, and it's also what makes the
   `attribute.environment` WIF condition in `bootstrap/main.tf`
   meaningful (see [docs/service-accounts.md](service-accounts.md) "No
   long-lived keys").

## Why re-validate in the apply pipeline

`apply.yml` re-runs `validate` + `render` from scratch rather than
trusting `plan.yml`'s artifacts. If `main` moved between the plan a human
approved and the apply actually running, the apply job validates the
*current* `main`, not the approved snapshot — an approval can never
rubber-stamp a config that changed after review. If you need strict
plan-then-apply-of-that-exact-plan semantics instead, download the plan
artifact `plan.yml` uploaded to
`gs://<artifact bucket>/deployments/<env>/<run id>/plan.json` and pass it
to `terraform apply` directly instead of re-planning.

## What this rebuild did not do

No workflow, WIF binding, GitHub Environment, or `bootstrap/grants/` apply
here has actually run — this repository has no connected GitHub remote
yet and this rebuild was explicitly code-only (see
[docs/troubleshooting.md](troubleshooting.md)). The YAML is real and
`terraform validate`/`fmt`/`plan` were run against every stack it
orchestrates (both `bootstrap/` and `bootstrap/grants/` plan cleanly
against placeholder project IDs), but the workflow steps themselves are
untested against a live GitHub Actions run, and `sit`/`uat`/`prod` are
still placeholder project IDs — nobody has applied `bootstrap/grants/`
against a real spoke project yet.
