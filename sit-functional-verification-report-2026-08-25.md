# sit — functional verification, 2026-08-25

Follow-up to the earlier full apply/teardown cycle the same day. That
round proved `terraform apply` succeeds for every resource type. This
round asked a different question: do the deployed resources actually
**work** — not just exist? Every test below exercised real, live GCP
infrastructure; nothing was simulated.

## Results

| Component | Test | Result |
|---|---|---|
| Cloud Run (`app-api`) | curl direct URL, unauthenticated | **403 — real bug found** |
| Cloud Run via `load_balancer` | curl public IP, unauthenticated | **403 — same bug, bigger blast radius** |
| Cloud Run (`app-api`) | curl direct URL, after fix | **200 — fixed and verified** |
| Cloud Run via `load_balancer` | curl public IP, after fix | **200 — fixed and verified, end-to-end** |
| Cloud Function (`process-upload`) | invoke via `.a.run.app` URL, internal | **403 — real bug found** |
| Cloud Function (`process-upload`) | invoke via `cloudfunctions.net` URL, after fix | **200 — real function logic response, fully verified** |
| Cloud SQL (`app-sql`) | MySQL login + query from inside VPC | **Success — real connection, real query result** |
| IAP tunnel (`admin-access` → `app-vm-01`) | real `gcloud compute ssh --tunnel-through-iap` | **Success — full tunnel + SSH + OS Login chain verified** |
| Binary Authorization | deploy an unattested test pod | **Correctly denied — first-ever real proof this control works** |
| Workload Identity | IAM binding present on real GCP | **Confirmed correct** (`roles/iam.workloadIdentityUser` on `prj-dg-devops-test-sit.svc.id.goog[default/app-ksa]`) — full pod-level runtime test skipped by choice, to avoid loosening Binary Authorization just to test a different feature |

## Two real bugs found and fixed

### 1. `modules/compute/cloudrun` had no invoker mechanism at all

`ingress: INGRESS_TRAFFIC_ALL` controls which *network paths* can reach
a Cloud Run service — it grants no IAM authorization. This platform's
own `app-api` + `app-lb` pair (a public load balancer built specifically
to expose this service) returned 403 through **both** the direct URL
and the load balancer's public IP, because nothing ever granted
`roles/run.invoker` to anyone.

Added `allow_unauthenticated` (bool, default `false` — secure by
default) and a conditional `google_cloud_run_v2_service_iam_member`
granting `roles/run.invoker` to `allUsers` when set. Set to `true` for
`app-api` **permanently** (not reverted) — its own load balancer's
stated purpose is meaningless without it, so this is a correctness fix
to the reference config, not a scope-expanding decision.

### 2. `modules/compute/cloudfunctions` had no invoker mechanism at all — and the fix needed a non-obvious resource type

Same root issue as `cloudrun`: `ingress_settings: ALLOW_INTERNAL_ONLY`
returned 403 to every caller, including a legitimate one inside the
same VPC (verified via a real IAP-tunneled SSH session into `app-vm-01`,
using the VM's own service account identity token).

The first fix attempt used `google_cloudfunctions2_function_iam_member`
with `roles/run.invoker` — rejected outright (`Invalid argument`). The
second attempt used the same resource with `roles/cloudfunctions.invoker`
— applied successfully, but `gcloud run services get-iam-policy` showed
the underlying Cloud Run service's own IAM policy was still completely
empty, and invocation still failed. **These are two separate ACLs**;
only the Cloud Run one actually gates HTTP invocation. The working fix:
`google_cloud_run_v2_service_iam_member` (same resource type as the
`cloudrun` fix) targeting the function's underlying Cloud Run service by
name.

Added `invoker_members` (list, default `[]` — deliberately closed, not
an `allow_unauthenticated` toggle like `cloudrun`, since an
`ALLOW_INTERNAL_ONLY` function should grant specific callers, never
`allUsers`). Verified end-to-end: granted the VM's identity temporarily,
got a real 200 with the function's actual JSON response
(`{"bucket":"test-bucket","name":"test-file.txt","status":"accepted"}`),
then reverted `invoker_members` back to `[]` — no real caller for this
function has been established yet, so closed-by-default is correct
until one is.

A third, smaller finding along the way: gen2 Cloud Functions expose two
distinct URLs (`*.a.run.app` and `*.cloudfunctions.net`) with different
behavior — internal-only invocation needs the `cloudfunctions.net` one.

## One genuinely positive result

Binary Authorization's `ALWAYS_DENY` default **correctly blocked** a
real test pod deploy on the real GKE cluster
(`admission webhook "imagepolicywebhook.image-policy.k8s.io" denied the
request ... Denied by always_deny admission rule`). `docs/testing.md`
had explicitly flagged this as "never proven to actually block a real
image deploy, only planned" — it's now proven, for real, positively.

This same result is also *why* Workload Identity's full runtime test
(deploying a pod that fetches a real GCP token) was skipped — doing so
would have required temporarily loosening a real, working security
control, and that trade-off wasn't made unilaterally. The IAM binding
itself was confirmed correct directly against real GCP instead.

## Teardown

Full teardown run immediately after, following the same
temporarily-unprotect-then-destroy pattern as every other cycle this
session (KMS `prevent_destroy`, `deletion_protection`/`force_destroy`
across `cloudsql`/`cloudrun`/`gke`/`workflows`/`bigquery`/`buckets`, plus
`--force-security` for the now-enforced `cloudsql`/`cloudrun`
ERROR-severity findings). Also hit, and worked around, the Cloud Tasks
queue-name-reuse cooldown a second time — this time it also interfered
with an unrelated targeted `apply` trying to fix `workflows`'
`deletion_protection`, resolved by temporarily disabling `cloudtasks`
entirely for that one apply rather than fighting the rename.

Final state: **31 resources remain**, same floor as the earlier cycle —
27 harmless API-enablement flags plus the identical `sit-vpc`/PSA
address/PSA connection/default route orphan, still blocked on the same
`FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION`-class GCP-side
condition documented repeatedly this session. Verified again: no real
producer (Cloud SQL, Redis) exists in the project.

All temporary config/module overrides reverted — confirmed via `git
diff` showing only the two permanent module fixes (`cloudrun`,
`cloudfunctions`), the `allow_unauthenticated: true` deliberate keep,
and a KMS comment update remain against the prior commit.

Raw logs kept locally (gitignored):
`sit-functional-verify-apply.log`, `sit-functional-verify-teardown.log`.
