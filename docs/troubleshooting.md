# Troubleshooting

## What this rebuild did and did not do

`bootstrap/` and `environments/dev` have both been applied for real against
`prj-dg-devops-test`, each with the user's explicit confirmation — see
"Bootstrap is now live" and "Dev was applied, then torn down" below.
`sit`/`uat`/`prod` and CI/CD triggers are still code-only. Read this before
calling anything here "production ready."

**Decided at the start:**
1. The previous local `terraform.tfstate` (which referenced a different
   project, `prj-dg-ml-prod-shared`) was archived, not migrated — this
   rebuild targets `prj-dg-devops-test` instead, a clean start rather than
   an import.
2. No local `git init` — `cicd/cloudbuild-*.yaml` are written as templates
   that assume a connected repository, not verified against one.

## Bootstrap is now live

`bootstrap/` was applied on 2026-08-18 against `prj-dg-devops-test`, after
explicit user confirmation (the sandbox's own permission system also
blocked the first `terraform apply -auto-approve` attempt and required an
unambiguous yes before allowing it — a deliberate guardrail, not a bug).
Real resources now exist:

- State bucket: `gs://prj-dg-devops-test-tfstate` (versioned, `public_access_prevention: enforced`, 90-day noncurrent-version lifecycle)
- Artifact bucket: `gs://prj-dg-devops-test-tf-artifacts` (180-day lifecycle)
- `tf-plan@prj-dg-devops-test.iam.gserviceaccount.com` (read-only)
- `tf-apply@prj-dg-devops-test.iam.gserviceaccount.com` (curated write roles)
- 6 APIs enabled (IAM, IAM Credentials, Resource Manager, Service Usage, Storage, STS)

**What actually happened during apply — a real incident, not a hypothetical:**
The first `terraform apply` hit `Error 409: ... you already own it` on
`google_storage_bucket.state` — the bucket creation request had actually
succeeded at the API level, but Terraform's own tracking of that call
failed, so its next attempt collided with the bucket it had already made.
Fixed by `terraform import`, which itself needed a second attempt: a plain
`terraform import google_storage_bucket.state prj-dg-devops-test-tfstate`
populated `project` as `null` in state (a known quirk — bucket GET doesn't
return project cleanly for this resource) and produced a plan that wanted
to **destroy and recreate the bucket** just to set `project` — refused,
since destroying a resource to fix a cosmetic state field is exactly the
kind of unnecessary churn to avoid. Re-imported with the composite
`project/bucket-name` ID form instead
(`prj-dg-devops-test/prj-dg-devops-test-tfstate`), which populated
`project` correctly, and the resulting plan was a clean in-place update
(add versioning + lifecycle rule + `public_access_prevention: enforced`,
0 destroys). Applied that; final `terraform plan` showed zero drift.
Worth knowing if you ever import a `google_storage_bucket` by hand: prefer
`<project>/<bucket>` over a bare bucket name.

**Not done yet**: `bootstrap/terraform.tfstate.bootstrap` (local) should be
copied to `gs://prj-dg-devops-test-tfstate/bootstrap/terraform.tfstate` as
the documented backup — attempted via `gsutil cp`, but both attempts
failed with `Reauthentication required.` (the gcloud CLI's own auth
session, separate from whatever the Terraform google provider used
successfully) and need an interactive `gcloud auth login` this session
can't do. Run manually:
```bash
gcloud auth login   # interactive — re-authenticate gsutil's session
gsutil cp bootstrap/terraform.tfstate.bootstrap gs://prj-dg-devops-test-tfstate/bootstrap/terraform.tfstate
```
`bootstrap/versions.tf` itself still points at local state either way, per
its own comment, until someone deliberately reconfigures it to the `gcs`
backend.

**What was verified, concretely:**
- `terraform fmt -check -recursive .` — clean.
- `terraform validate` — passes for `bootstrap/` and all four
  `environments/<env>/` stacks.
- `terraform plan` for `environments/dev` — run twice, manually, against
  the real `prj-dg-devops-test` project (read-only, no `-out` retained,
  nothing applied) via a temporary local-backend override that was never
  committed. Clean, zero errors both times (82 resources, then 99 after
  adding GKE/Cloud Functions/Memorystore/VPC Service Controls), and caught
  two real bugs in the process (see `docs/modules.md`, `docs/testing.md`).
- `terraform apply` for `bootstrap/` — live, against real GCP, described
  above. Follow-up `terraform plan` confirms zero drift.
- `pytest tests/` — 14/14 passing, including the exact "reject an invalid
  config" scenario the platform spec asked for.
- `python -m engine.cli hardcode-scan .` — 0 findings across `modules/`,
  `platform/`, `bootstrap/`.

## Dev was applied, then torn down (2026-08-18)

With explicit user confirmation, `environments/dev` was applied for real
against `prj-dg-devops-test` (99 resources), then destroyed at the user's
request once three real bugs turned up. Full sequence, because each step
taught something worth keeping:

**The apply — three real bugs found, none of them GKE-cluster-taints or
made up:**
1. **Cloud Function 404** — `cloudfunctions.process-upload`'s
   `source.object` (`functions/process-upload.zip`) doesn't exist in the
   bucket. Not a Terraform bug — Cloud Functions genuinely needs
   already-uploaded source code, which this example never had. Now
   disabled by default with an explanatory comment in `deployment.yaml`
   rather than left as a guaranteed-to-fail placeholder.
2. **Cloud Run 403** — `cloudrun.app-api`'s image
   (`asia-south1-docker.pkg.dev/cloudrun/container/hello`) isn't
   accessible. Google's public "hello" sample is only published at the
   multi-region `us-docker.pkg.dev` host, not per-region mirrors — the
   original repo's example config had the wrong host. Fixed in
   `deployment.yaml`.
3. **GKE node unhealthy** — the cluster itself was created, but its node
   never went healthy: the CNI plugin never initialized, and the node
   timed out pulling the base `pause` image from the regional Artifact
   Registry mirror. This looks like a real egress-routing gap for
   private-node GKE reaching `gcr.io`/`pkg.dev` through this VPC's Cloud
   NAT — **not root-caused**, flagged with a comment on the `gke` block in
   `deployment.yaml`. If you hit this again: check whether Private Google
   Access / Cloud NAT actually covers the container registry endpoints
   this GKE version pulls from, and whether the private cluster's DNS
   resolution for regional Artifact Registry mirrors is working at all.

**The teardown — deletion_protection interacts with destroy in ways worth
knowing before you hit them:**
- `terraform destroy` (and `plan -destroy`) **cannot** touch a resource
  with `lifecycle.prevent_destroy` (the KMS crypto keys) — by design, no
  way around it short of removing the resource from state, which wasn't
  attempted since GCP KMS keys can't be hard-deleted via API anyway (see
  `docs/security.md`).
- `deletion_protection = true` (GKE cluster, Cloud SQL instance, BigQuery
  tables) blocks deletion differently: it's checked against the **state's
  currently recorded value**, not the desired end-state. Simply setting
  `resources.<type>.enabled: false` and applying does NOT flip protection
  off first — Terraform tries to delete directly and fails. The correct
  sequence is two separate applies: (1) with the resource still enabled,
  set `deletion_protection: false` and apply that as an in-place update;
  (2) only then set `enabled: false` and apply/destroy.
- `-target` on a module pulls in the **full transitive dependency
  closure**, including modules that seem unrelated. Targeting `apis` (or
  any module most other modules `depends_on`) drags in everything
  downstream, because Terraform must destroy dependents before a
  dependency. Solution: don't target foundational modules you want to
  keep (here, `apis`, `kms`, `pubsub` were deliberately left out of every
  targeted destroy).
- A cluster whose creation partially fails (API call succeeded, the
  "wait until healthy" check didn't) gets marked **tainted** — the next
  plan wants to destroy-and-recreate it, even for an otherwise-unrelated
  change like flipping `deletion_protection`. `terraform untaint
  '<resource address>'` clears this safely (state-only, zero API calls)
  without forcing a rebuild.
- After the Cloud SQL instance was deleted, its Private Service Access
  peering connection (`google_service_networking_connection`) refused to
  delete with `Producer services ... are still using this connection` for
  over 15 minutes, confirmed via `gcloud sql instances list` /
  `gcloud redis instances list` that nothing was actually still attached.
  This is a known Google Cloud backend propagation delay after deleting
  the last Cloud SQL/Memorystore instance on a peering connection — not a
  Terraform or config problem. At the user's direction, this was left
  as-is rather than retried indefinitely (a VPC + idle peering connection
  costs nothing).

**End state**: everything that bills is gone. `apis`, `kms` (keyring + 4
keys), and `pubsub` (topic + subscription) were deliberately kept enabled
— all free to leave idle. The VPC and its Private Service Access
connection may still exist depending on whether the backend delay above
has cleared; check with `terraform state list` in `environments/dev`.
`config/environments/dev/deployment.yaml` was restored afterward to a
normal, re-deployable state (all types re-enabled except `cloudfunctions`
and `vpc_service_controls`, `deletion_protection` restored to `true`
everywhere).

**Not verified — genuine gaps, not oversights:**
- `sit`/`uat`/`prod` have never been applied.
- `cicd/cloudbuild-*.yaml` has never triggered a real Cloud Build run.
- Workload Identity Federation is authored (`bootstrap/main.tf`, off by
  default) but never created.
- No integration test applies real infrastructure and tears it down.
- Cost validation is a static price table, not a live Cloud Billing
  lookup (see `docs/validation.md`).
- `sit`, `uat`, and `prod` `deployment.yaml` are templates (apis + vpc
  only) — no real workload configuration existed for them in the original
  repository, so none was fabricated here.

## Common issues

**`terraform plan` fails with "Backend initialization required"**
You changed `backend "gcs" {}` config (or are running for the first time)
without providing `-backend-config=`. See
[docs/state-management.md](state-management.md).

**`python -m engine.cli render` refuses to write the JSON file**
Validation is blocked — read the printed report, fix the ERROR-severity
findings, re-run. This is deliberate: it's the actual mechanism that stops
an invalid config from reaching Terraform (see
[docs/validation.md](validation.md)).

**A module I added isn't being created even though I set `enabled: true`**
Check `platform/locals.tf` `local.resource_types` — a resource type not
listed there is silently treated as disabled everywhere. See
[docs/modules.md](modules.md) "Adding a new module."

**`engine/hardcode_scanner.py` flags something that's actually fine**
Add a trailing `# hardcode-allow: <reason>` comment on that line — sparing
use only, see the scanner's module docstring.

**I need per-layer state separation (foundation/network/security/...)**
Not implemented — see [docs/state-management.md](state-management.md)
"Why one state file per environment for now" for the reasoning and the
concrete steps to do it when you actually need it.
