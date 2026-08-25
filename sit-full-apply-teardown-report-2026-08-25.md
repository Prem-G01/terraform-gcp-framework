# sit — full real apply + teardown, 2026-08-25

Complete record of the full-scope real apply (all 34 resource types except
the deliberately-skipped `org_policies`) against `prj-dg-devops-test-sit`,
and the subsequent full teardown. Raw terraform output for both phases is
preserved alongside this file:

- `sit-apply-full.log` (2,619 lines) — the real apply
- `sit-destroy-full.log` (12,503 lines) — all destroy attempts, including
  the two blockers hit and fixed along the way

## Phase 1 — Apply: what was deployed

Peak state: **112 real resources**, across 30 of 31 enabled resource types
(`org_policies` deliberately disabled for this cycle — see
`docs/troubleshooting.md` "org_policies is a permanent, deliberate
limitation").

| Resource type | Count | Notes |
|---|---|---|
| apis (`google_project_service`) | 27 | Every API this platform's config enables |
| service_accounts | 23 | 6 SAs + 17 IAM role bindings |
| secrets | 6 | 2 secrets × (secret + version + random_password) |
| load_balancer | 6 | IP, backend, NEG, HTTP proxy, forwarding rule, URL map |
| alert_policies | 6 | vm-cpu, vm-disk, cloudsql-cpu, gke-node-cpu, memorystore-memory-usage, cloudfunctions-errors |
| kms | 5 | 1 keyring + 4 crypto keys |
| cloudsql | 3 | 1 instance + 2 users |
| bigquery | 3 | 1 dataset + 2 tables |
| artifact_registry | 3 | docker, python, maven repos |
| vpc | 2 | network + default route |
| pubsub | 2 | 1 topic + 1 subscription |
| private_service_access | 2 | reserved IP range + peering connection |
| logging | 2 | app-logs, audit-logs buckets |
| gke | 2 | 1 cluster + 1 node pool |
| firewall | 2 | allow-iap, allow-internal |
| documentai | 2 | invoice, ocr processors |
| buckets | 2 | app-storage, tf-backup |
| workload_identity | 1 | |
| workflows | 1 | |
| vm | 1 | |
| uptime_checks | 1 | |
| subnet | 1 | |
| scheduler | 1 | |
| router | 1 | |
| notification_channels | 1 | |
| nat | 1 | |
| memorystore | 1 | |
| cloudtasks | 1 | |
| cloudrun | 1 | |
| cloudfunctions | 1 | |
| binary_authorization | 1 | |
| **Total** | **112** | |

### Two real bugs found and fixed mid-apply

1. **Workflows service agent didn't exist.** `Error 400: Workflows
   service agent does not exist`. Real cause: enabling
   `workflows.googleapis.com` doesn't always auto-provision its service
   identity immediately on a brand-new project. Fixed with
   `gcloud beta services identity create --service=workflows.googleapis.com`,
   then the resource applied cleanly on retry — confirming this was a
   real provisioning-timing issue, not a permission gap.

2. **Cloud Functions gen2 build failed — missing permission on the build
   service account.** The Compute Engine default service account
   (`758025978407-compute@developer.gserviceaccount.com`, used by Cloud
   Build for gen2 function builds since GCP's 2024+ default-project IAM
   changes) had zero IAM roles on this brand-new project. Fixed by
   granting it `roles/cloudbuild.builds.builder`; the function then
   built and deployed successfully.

Neither issue is a bug in this platform's own code — both are real,
project-lifecycle-specific GCP quirks that only surface on a genuinely
new project's very first use of these two services.

## Phase 2 — Destroy: what was deleted

Final state after teardown: **31 resources remain** (down from 112 — 81
resources confirmed destroyed).

### What's still there, and why

| Remaining | Count | Status |
|---|---|---|
| `google_project_service.apis[*]` | 27 | Harmless — API enablement flags, zero cost, no real infrastructure. Left as-is. |
| `google_compute_network.vpc["sit-vpc"]` | 1 | **Genuinely stuck** |
| `google_compute_route.default_internet_gateway["sit-vpc"]` | 1 | **Genuinely stuck** |
| `google_compute_global_address.private_ip["psa-sit"]` | 1 | **Genuinely stuck** |
| `google_service_networking_connection.private_connection["psa-sit"]` | 1 | **Genuinely stuck** |

The 4 "genuinely stuck" resources are blocked by the identical
`FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION`-class error that also
blocked `dev`'s teardown earlier this session — a documented, unresolved
GCP-side backend condition, **not** a real attached producer. Verified
directly: `gcloud sql instances list` and `gcloud redis instances list`
both return empty for `prj-dg-devops-test-sit` (Cloud SQL and Memorystore,
the only real producers, were both already destroyed by the time this was
checked). Retried the destroy twice; identical failure both times. Same
conclusion as `dev`'s incident: this needs to clear on GCP's side, not
something retrying or reconfiguring fixes.

### Two real blockers hit and fixed during teardown

1. **KMS `prevent_destroy`** — temporarily flipped to `false` in
   `modules/security/kms/main.tf`, restored to `true` immediately after
   all 5 KMS resources were confirmed destroyed. GCP still has no API to
   hard-delete a KMS key/keyring regardless; this only let Terraform
   untrack them.

2. **`deletion_protection`/`force_destroy` guards** on `cloudsql`,
   `cloudrun`, `gke`, `workflows`, `bigquery` (both tables), and both
   `buckets` — all temporarily overridden in
   `config/environments/sit/deployment.yaml` with `# TEMP (2026-08-25)`
   comments, applied via `--force-security` (cloudsql/cloudrun's
   overrides are ERROR-severity security findings —
   `SEC_SQL_NO_DELETION_PROTECTION` / `SEC_CLOUDRUN_NO_DELETION_PROTECTION`
   — that need the audited break-glass override to render through). All
   reverted to their correct values immediately after teardown; verified
   via `git diff` that only comment/documentation changes remain against
   the last commit.

3. **Logging buckets stuck `DELETE_REQUESTED`** — `app-logs` and
   `audit-logs` landed in a stuck transitional state during a procedural
   misstep (see below), fixed with `gcloud logging buckets undelete` +
   `terraform untaint`, the same established fix used for this exact
   issue on `dev` earlier in the session.

### A real procedural inefficiency, disclosed honestly

The first attempt to apply the unprotect changes used a full,
untargeted `terraform apply` rather than one scoped to just the
resources needing their protection flags updated. Because the first
destroy attempt (blocked purely by KMS's `prevent_destroy`) had failed
*before* destroying anything — Terraform validates all
`lifecycle.prevent_destroy` constraints across the whole plan before
executing any destroy action — the state was still fully intact at that
point, so no harm resulted from that specific ordering.

However, once real resources genuinely started being destroyed in later
attempts (router, firewall, load balancer pieces, memorystore, GKE node
pool all succeeded), a subsequent full `apply` — run to fix the
`deletion_protection` flags — saw those resources missing from state
while the config still declared them enabled, and **recreated** them
(router, notification channels, uptime checks, Document AI processors,
Cloud Functions, artifact registries, Binary Authorization policy, and
both logging buckets). This is what caused the logging buckets' stuck
`DELETE_REQUESTED` state above — they were deleted, then recreated by
the same-day recreate, landing in a delete/recreate race.

No lasting harm: everything recreated this way was destroyed again in
the final teardown pass along with everything else. But it meant extra
real GCP API calls and about 10 extra minutes of real time that a
correctly `-target`-scoped apply would have avoided. Noted here plainly
rather than glossed over.

## Bottom line

- **112 resources deployed for real, 81 confirmed destroyed.**
- **27 remaining are harmless** (API flags only, zero cost).
- **4 remaining are genuinely stuck** on the same unresolved GCP-side
  condition already documented for `dev` — needs time to clear, not a
  code or config problem. Manual cleanup once it does:
  ```bash
  gcloud services vpc-peerings delete --network=sit-vpc --project=prj-dg-devops-test-sit
  gcloud compute networks delete sit-vpc --project=prj-dg-devops-test-sit
  ```
- **All temporary config/module changes have been reverted** — confirmed
  via `git diff` showing only comment additions remain.
- **Two real, previously-unknown GCP-project-lifecycle bugs found and
  fixed** (Workflows service agent provisioning, Cloud Build default SA
  permissions) — both now documented for any future new-project apply.
