# Troubleshooting

## What this rebuild did and did not do

`bootstrap/` and `environments/dev` were both applied for real against
`prj-dg-devops-test` on 2026-08-18 (a since-superseded single-shared-SA
design), then both fully destroyed the same day. `bootstrap/` was
rewritten to the current dedicated-per-environment design and **applied
for real again on 2026-08-19** — see "Bootstrap re-applied (per-
environment design), 2026-08-19" below; that section, not "Bootstrap is
now live", describes current reality. `environments/dev` has NOT been
re-applied with the current design yet. `sit`/`uat`/`prod` and CI/CD
triggers have never been applied. Read this before calling anything here
"production ready," and read the dated section headers in order — an
earlier section can be fully superseded by a later one.

**Decided at the start:**
1. The previous local `terraform.tfstate` (which referenced a different
   project, `prj-dg-ml-prod-shared`) was archived, not migrated — this
   rebuild targets `prj-dg-devops-test` instead, a clean start rather than
   an import.
2. No local `git init` — `.github/workflows/*.yml` are written as
   templates that assume a connected GitHub repository, not verified
   against one.

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
   Registry mirror.

   **Likely root cause found afterward, not yet re-verified against a live
   cluster**: `modules/networking/vpc` sets `delete_default_routes_on_create`
   from config, and `dev-vpc`'s config has it `true` — this deletes the
   VPC's `0.0.0.0/0` route to the default internet gateway. **Cloud NAT
   does not create that route itself** — NAT only translates traffic that's
   already being routed to the internet gateway; delete the default route
   and never replace it, and NAT is fully configured but has nothing to
   attach to. Every private-IP-only resource in the VPC (the GKE node
   included) would have had zero path to the internet, which fully
   explains a registry-pull timeout. Fixed by adding
   `google_compute_route.default_internet_gateway` to
   `modules/networking/vpc/main.tf` — created automatically whenever
   `delete_default_routes_on_create` is true, opt out per-VPC with
   `create_default_internet_route: false`. Verified this plans cleanly
   (read-only, against the real project) but **the fix has not yet been
   proven against a real GKE node** — that requires actually redeploying
   GKE, a real cost/time decision left to whoever does that next. If a
   node is still unhealthy after this fix, the earlier hypotheses (Private
   Google Access coverage, regional Artifact Registry DNS resolution)
   are the next things to check.

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
- `.github/workflows/*.yml` has never triggered a real GitHub Actions run
  — this repo previously (briefly) provisioned a GCP-hosted git repo via
  Secure Source Manager instead of using GitHub; that was reverted once
  GitHub + GitHub Actions was chosen as the actual CI/CD path (see
  `bootstrap/main.tf` git history).
- Workload Identity Federation is authored (`bootstrap/main.tf`, off by
  default) but never created — needs a real `github_repository` value.
- `bootstrap/main.tf` was rewritten after the teardown below to grant a
  dedicated `tf-plan-<env>`/`tf-apply-<env>` pair per environment instead
  of one shared pair, and `bootstrap/grants/` (a new, separate stack) was
  added for granting those identities roles in `sit`/`uat`/`prod`'s own
  projects. Both plan cleanly (`terraform plan` against placeholder
  project IDs — 56 and 22 resources respectively, 0 errors) but neither
  has been applied for real; the per-environment design was never live.
- No integration test applies real infrastructure and tears it down.
- `validate`/`render` cost validation is still a static price table, not
  a live lookup — deliberately, to keep those fast and credential-free
  (see `docs/validation.md`). `python -m engine.cli cost-check-live` (new,
  see `engine/live_cost.py`) is a real live Cloud Billing Catalog
  integration, tested for real against `asia-south1` while building it —
  but scoped to Compute Engine `*-standard-N` shapes only; shared-core
  VMs and all of Cloud SQL still fall back to the static table.
- `sit`, `uat`, and `prod` `deployment.yaml` are templates (apis + vpc
  only) — no real workload configuration existed for them in the original
  repository, so none was fabricated here.

## Full teardown (bootstrap + the last of dev), 2026-08-18

At explicit user request ("delete everything, it was all for testing —
including bootstrap"), the rest of `dev` and all of `bootstrap` were
destroyed. Two more real incidents, and the final honest state:

**The dev-vpc / Private Service Access connection took over an hour to
release.** `google_service_networking_connection.private_connection`
refused to delete with `Producer services ... are still using this
connection` across roughly six retries spanning well over an hour, even
though `gcloud sql instances list` and `gcloud redis instances list`
confirmed nothing was actually attached. Direct `gcloud services
vpc-peerings delete` hit the identical error with a specific reason code
(`FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION`) that this session
couldn't resolve further. This blocked `dev-vpc` (a VPC can't be deleted
with an active peering) and transitively blocked the 24 `apis` entries (a
reverse dependency of `vpc`). Everything else in `dev` — Pub/Sub, and
after temporarily disabling KMS's `prevent_destroy` (see below) the KMS
keyring and its 4 keys — was destroyed successfully before this session's
Terraform tracking of `dev` was intentionally given up (see the state
bucket deletion below). **If `prj-dg-devops-test` still has a `dev-vpc`
network and a `psa-dev`-named Private Service Access peering/reserved
range, that's this leftover** — clean it up manually
(`gcloud compute networks delete dev-vpc`, and the associated peering)
once GCP's backend has actually released the connection; there's no
Terraform state left to do it through anymore.

**KMS's `prevent_destroy` was temporarily set to `false`.** GCP has no API
to hard-delete a KMS key or keyring at all — "destroying" a
`google_kms_crypto_key`/`google_kms_key_ring` resource only removes it
from Terraform state, it never calls a real delete. `prevent_destroy` was
flipped back to `true` in `modules/security/kms/main.tf` immediately after
this teardown; it should never normally be `false`.

**The state bucket's `force_destroy` didn't actually work.** Even with
`force_destroy = true` set in `bootstrap/main.tf` and re-applied,
`terraform destroy` failed twice with `Error trying to delete bucket ...
without force_destroy set to true` — despite the config already saying
so. The bucket had accumulated dozens of noncurrent object versions
(`default.tfstate#<generation>`, `default.tflock#<generation>`) from every
render/plan/apply cycle across this whole session, and the provider's
`force_destroy` object-emptying logic didn't reliably clear all of them.
Worked around by emptying and deleting the bucket directly —
`gcloud storage rm --recursive gs://prj-dg-devops-test-tfstate/**` then
`gcloud storage buckets delete gs://prj-dg-devops-test-tfstate` — which
succeeded immediately. `force_destroy` was restored to `false` in
`bootstrap/main.tf` afterward (it should never normally be `true` — this
was flagged to and confirmed by the user before doing it, given it meant
giving up Terraform's tracking of the still-real `dev-vpc`/peering
resources above). The artifact bucket (no versioning, no accumulated
history) destroyed cleanly via plain `terraform destroy` with no
workaround needed.

**Final state**: `bootstrap`'s Terraform state has 0 resources. Every
service account, IAM binding, and both buckets it created are gone. The
one thing this repo cannot claim is fully cleaned up is the `dev-vpc`
network and its Private Service Access peering — real, but no longer
tracked by any Terraform state in this repository.

### Follow-up cleanup attempt, still 2026-08-18

Retried `gcloud services vpc-peerings delete --network=dev-vpc` directly
later the same day — **identical failure**, same reason code
(`FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION`, "Producer services
... are still using this connection"). Checked every producer type that
uses Service Networking peering before retrying, to rule out something
this repo missed: `gcloud sql instances list`, `gcloud redis instances
list`, `gcloud filestore instances list`, `gcloud container clusters
list` all returned zero results, and AlloyDB's API isn't even enabled on
this project. `gcloud compute networks peerings list` shows the peering
itself as `ACTIVE`/`Connected`, and `gcloud compute addresses list` shows
only the expected reserved range (`google-managed-services-dev`) — no
actual attached resource anywhere this session can see.

This looks like the documented GCP-side eventual-consistency issue where
the Service Networking backend's own internal reconciliation lags well
behind reality, sometimes for a day or more, independent of anything a
consumer project can do. Retrying the `gcloud` command again immediately
won't help — there's nothing left to fix on this project's side. If this
is still blocked whenever you next check: retry the same
`gcloud services vpc-peerings delete --network=dev-vpc --project=prj-dg-
devops-test` command after waiting longer, or open a GCP support case
citing the reason code above. No cost accrues while it sits idle (an
unused VPC network and reserved peering range aren't billed), so there's
no urgency pressure beyond wanting Terraform-clean state.

## Bootstrap re-applied (per-environment design), 2026-08-19

`bootstrap/`'s current dedicated-per-environment design (see git history —
"Dedicated per-environment SAs, cross-project grants, centralized
logging") was applied for real against `prj-dg-devops-test`, after
explicit user confirmation at each step (a `terraform plan` reviewed
first, then a separate confirmation before `apply`). 56 resources, real:

- State bucket: `gs://prj-dg-devops-test-tfstate-v2` (note the `-v2` —
  see the incident below)
- Artifact bucket: `gs://prj-dg-devops-test-tf-artifacts`
- Central log bucket: `gs://prj-dg-devops-test-logs`, with `dev`'s
  `google_logging_project_sink` wired to it
- 8 dedicated service accounts: `tf-plan-<env>`/`tf-apply-<env>` for
  `dev`/`sit`/`uat`/`prod`, all in `prj-dg-devops-test`
- `dev`'s (this apply's `home_environment`) `tf-apply`/`tf-plan` pair
  has its full curated role set granted; `sit`/`uat`/`prod`'s pairs
  exist as identities only, no roles anywhere yet — that's
  `bootstrap/grants/`'s job, pending real (currently placeholder)
  project IDs for those three
- 7 APIs enabled

**A real incident, not a leftover from our own history this time.** The
apply got partway through — 47 of 56 resources created (all the SAs,
role bindings, `artifacts`/`logs` buckets) — then failed on
`google_storage_bucket.state` with `Error 409: ... you already own it`.
Investigated before assuming anything: `gcloud storage buckets describe
gs://prj-dg-devops-test-tfstate` showed a bucket created that same day
(`2026-08-19T06:02:53Z`) containing `audit-platform/state/default.tfstate`
— a real, different Terraform project's state, not ours, not created by
this session. Something else — another engineer, another automation, an
unrelated Claude session — claimed that exact bucket name in this shared
test project sometime between the 2026-08-18 teardown and this apply.
Left it completely untouched (never deleted, never imported, never
inspected beyond `describe`) and used a different name instead
(`prj-dg-devops-test-tfstate-v2`, confirmed with the user first) to
finish the remaining 9 resources (the state bucket itself + 8 per-
environment IAM bindings on it). If you're reusing this project for
other work, `prj-dg-devops-test-tfstate` is not available and something
called "audit-platform" is real and running there — worth knowing who
owns it before it surprises the next person.

`bootstrap/terraform.tfstate.bootstrap` was copied to
`gs://prj-dg-devops-test-tfstate-v2/bootstrap/terraform.tfstate` as a
backup immediately after — the "still pending" backup step from the
2026-08-18 incident, actually done this time.

**Not yet done**: `environments/dev` has not been re-applied against
this bootstrap. WIF is still off (`enable_workload_identity_federation =
false` — no `github_repository` value yet). `bootstrap/grants/` has not
been applied against any real `sit`/`uat`/`prod` project.

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
