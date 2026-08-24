# Security model

## Secure by default

`config/global/defaults.yaml` `security_defaults` sets the platform-wide
posture (no public IPs, OS Login on, Shielded VM fully on, uniform bucket
access + enforced public-access-prevention, Cloud SQL private-only +
deletion protection, KMS `prevent_destroy` + 90-day rotation). These are
applied as Terraform fallbacks (`lookup(each.value, "field", secure_default)`
inside `modules/*/main.tf`) — an engineer can still override them per
instance in `deployment.yaml`, but doing so is exactly what the security
engine (below) exists to catch.

**`deletion_protection`, specifically**, exists on 8 of this platform's
resource types (audited directly against the installed provider schema,
not assumed): `cloudsql`, `gke`, `bigquery` (tables), `workflows`,
`cloudrun`, `vm`, `memorystore`, and `secrets`. Every one of them exposes
it via `lookup(each.value, "deletion_protection", <default>)` — but the
default genuinely differs by category, not a uniform `true`:

- **`true`** for `cloudsql`, `gke`, `bigquery`, `workflows`, `cloudrun` —
  managed data stores / application-tier resources where an accidental
  delete is costly and replacement isn't a routine operation.
- **`false`** (GCP's own native default) for `vm`, `memorystore`,
  `secrets` — infra-plumbing/ephemeral resources where routine lifecycle
  operations (a `machine_type` change forces `google_compute_instance`
  replacement; a cache or a regeneratable secret isn't durable state)
  would otherwise be blocked by a protection flag that doesn't map to a
  real risk for that resource type. Opt in per-instance where it
  genuinely applies (e.g. a VM that shouldn't be casually replaced).

Only `cloudsql`'s is enforced at ERROR severity
(`SEC_SQL_NO_DELETION_PROTECTION` below) — the others are a safe
default, not a validated policy, so an explicit `false` in
`deployment.yaml` is allowed and not flagged for the rest.

## Enforced by the validation engine

`config/global/security.yaml` is the rule catalogue — id, which resource
types it applies to, severity, human description. `engine/security_engine.py`
implements the actual condition for each rule (there's no generic policy
DSL; see that file's docstring for why). Current rules:

| Rule | Type | Severity | Catches |
|---|---|---|---|
| SEC_PUBLIC_SSH | firewall | ERROR | TCP/22 open from 0.0.0.0/0 |
| SEC_PUBLIC_RDP | firewall | ERROR | TCP/3389 open from 0.0.0.0/0 |
| SEC_FIREWALL_OPEN_INGRESS | firewall | ERROR | any protocol, no port restriction, from 0.0.0.0/0 |
| SEC_PUBLIC_VM | vm | ERROR | `network.public_ip: true` |
| SEC_MISSING_OS_LOGIN | vm | ERROR | `metadata['enable-oslogin'] != "TRUE"` |
| SEC_MISSING_SHIELDED_VM | vm | ERROR | secure_boot/vtpm/integrity_monitoring not all true |
| SEC_OVERPRIVILEGED_SERVICE_ACCOUNT | service_accounts | WARNING | roles/owner, roles/editor, or `*.admin` |
| SEC_PUBLIC_BUCKET | buckets | ERROR | not `public_access_prevention: enforced` + uniform access |
| SEC_PUBLIC_SQL | cloudsql | ERROR | `network.ipv4_enabled: true` |
| SEC_SQL_NO_DELETION_PROTECTION | cloudsql | ERROR | `deletion_protection: false` |
| SEC_KMS_ROTATION_MISSING | kms | WARNING | crypto key with no `rotation_period` |
| SEC_SECRET_TOO_SHORT | secrets | WARNING | length below `security_defaults.secrets.min_length` |
| SEC_GKE_PUBLIC_CLUSTER | gke | ERROR | `private_cluster.enable_private_nodes: false` |
| SEC_REDIS_AUTH_DISABLED | memorystore | ERROR | `auth_enabled: false` |
| SEC_REDIS_UNENCRYPTED_TRANSIT | memorystore | ERROR | `transit_encryption_mode: DISABLED` |
| SEC_CLOUDFUNCTION_PUBLIC_INGRESS | cloudfunctions | WARNING | `ingress_settings: ALLOW_ALL` (legitimate for webhooks — flagged for confirmation, not blocked) |

## VPC Service Controls — read before enabling

`modules/security/vpc_service_controls` is the one resource type in this
platform capable of breaking every other resource type at once: a
misconfigured service perimeter can cut the project off from the very APIs
(Storage, BigQuery, Secret Manager, ...) every other module depends on.
Two things make it different from every other module here:

1. **`google_access_context_manager_access_policy` is a singleton per GCP
   organization.** If your org already has one (`gcloud
   access-context-manager policies list`), set
   `resources.vpc_service_controls.existing_access_policy_id` to it and
   leave `create_access_policy: false`. Only set `create_access_policy:
   true` when bootstrapping a brand-new org that has never had one —
   running it against an org that already has a policy fails outright.
2. **It's shipped disabled** in every environment's `deployment.yaml`
   (`resources.vpc_service_controls.enabled: false`) — deliberately, not
   as an oversight. Enabling it is a decision to make deliberately, per
   project, with the actual `restricted_services` list your org needs,
   not by copying an example.

Severity lives in YAML, not code — downgrading `SEC_PUBLIC_SSH` from ERROR
to WARNING (never recommended) is a one-line config change reviewable in a
PR diff, not a code change. An unknown/typo'd rule id falls back to ERROR
(`_severity()` in `engine/security_engine.py`), so a mistake in the policy
file can't silently disable a check.

## Org policy constraints

`modules/security/org_policies` is the project-level backstop behind
every `SEC_*` rule above — those rules only catch what's written in
`deployment.yaml` before a plan runs; org policy constraints are enforced
by GCP itself against every API call to the project, including a direct
console/gcloud change that bypasses this framework's pipeline entirely.
Five constraints, all project-scoped (no `organization_id` needed, unlike
VPC Service Controls), all enforced by default:

| Constraint | Backstops |
|---|---|
| `iam.disableServiceAccountKeyCreation` | This platform's own no-keys design (see docs/service-accounts.md) — blocks anyone from creating a downloadable SA key JSON at all |
| `compute.vmExternalIpAccess` (deny all) | SEC_PUBLIC_VM |
| `sql.restrictPublicIp` | SEC_PUBLIC_SQL |
| `compute.requireOsLogin` | SEC_MISSING_OS_LOGIN |
| `compute.skipDefaultNetworkCreation` | Nothing directly — a new project's auto-mode "default" VPC has permissive default firewall rules and this platform never uses it, so it's pure attack surface |

Unlike VPC Service Controls, there's no reason to ship this disabled —
enable it in every environment (`resources.org_policies.enabled: true`),
loosen an individual field only with a deliberate, reviewable
`deployment.yaml` change.

**A real permission gap found applying this for real (2026-08-19)**:
`google_org_policy_policy` needs `orgpolicy.policies.create`
(`roles/orgpolicy.policyAdmin` or broader) on whoever's identity applies
it — a real human account with broad-looking access elsewhere in a
project (create VPCs, SAs, IAM bindings, ...) is not guaranteed to have
this specific permission, since it's narrower and more sensitive than
general project resource administration. Confirm the applying identity
actually has it before assuming `org_policies` will apply cleanly — see
[docs/troubleshooting.md](troubleshooting.md) "environments/dev applied
for real" for what this looked like in practice (a real `403:
IAM_PERMISSION_DENIED`, distinct from and only visible after fixing the
separate ADC quota-project routing issue documented in the same
section).

## Identity-Aware Proxy

`modules/security/iap` replaces "trusted because it came from the right
network range" with "trusted because IAM says so, checked per request."
The `allow-iap` firewall rule (source range `35.235.240.0/20`, Google's
fixed IAP relay — see `config/environments/dev/deployment.yaml`
`firewall.instances.allow-iap`) only lets IAP's own traffic reach an
instance at all; this module is what actually authorizes *who* gets to
open a tunnel through it, via `google_iap_tunnel_instance_iam_member`
bindings scoped to one VM at a time — never a project-wide grant.

Shipped enabled with zero members (`resources.iap.instances.admin-access
.members: []`) — the wiring is live and tested, but nobody has tunnel
access until you add real principals
(`"group:platform-admins@yourdomain.com"`, `"user:name@yourdomain.com"`).
Deny-by-default, same posture as everything else in this section.

## GKE Workload Identity

Every cluster `modules/compute/gke` creates already always has
`workload_identity_config` and `workload_metadata_config = GKE_METADATA`
on (not a config toggle — there's no legitimate case here for a cluster
with it off). That's necessary but not sufficient: in `GKE_METADATA`
mode, a pod with no explicit binding gets **no** GCP identity at all
(metadata-server access is blocked outright, it does not fall back to the
node pool's SA) until `modules/security/workload_identity` binds its
Kubernetes ServiceAccount to a real, narrowly-scoped GCP service account
via `roles/iam.workloadIdentityUser`. That's the actual zero-trust
property: a compromised pod can reach only the one GCP service account
its own KSA was explicitly bound to, never the node's SA and never
another workload's SA.

`k8s_namespace`/`k8s_service_account` name Kubernetes-side objects this
platform doesn't create (it provisions cluster infrastructure, not
application manifests) — create a matching `ServiceAccount` in that
namespace, annotated `iam.gke.io/gcp-service-account: <the GCP SA
email>`, when you actually deploy the workload.

## Binary Authorization

`modules/security/binary_authorization` sets the project's default image
admission policy; `modules/compute/gke`'s `enable_binary_authorization`
var (wired automatically from `resources.binary_authorization.enabled`
in `platform/main.tf`) is what makes a given cluster actually enforce it
— a project policy alone enforces nothing on GKE until a cluster opts in.

This defends against a different attacker model than everything else in
this doc: identity-based controls (curated SA roles, WIF, IAP) stop an
*unauthorized deployer*; Binary Authorization stops an *unverified image*
— relevant even against a fully-authorized, correctly-scoped
`tf-apply-<env>` or a legitimate developer, if the image itself wasn't
built by a trusted pipeline.

**Deliberately does not create attestors.** A real attestor needs real
cryptographic signing key material tied to your org's actual build
pipeline (Cloud Build, or whatever CI produces the image) — fabricating
placeholder key material here would be security theater, not security.
Shipped as `evaluation_mode: ALWAYS_DENY` (blocks every image — the safe
starting point with no attestors set up yet). Once you have a real
signer, create `google_binary_authorization_attestor` resources
separately, list their names in
`resources.binary_authorization.require_attestations_by`, and switch
`evaluation_mode` to `REQUIRE_ATTESTATION`. Consider
`enforcement_mode: DRYRUN_AUDIT_LOG_ONLY` first, to see what the policy
would have blocked before it can actually break a real deploy.

## What this replaced

The original repo's dev config already had good instincts (IAP-only
firewall ranges, Shielded VM, `enforced` bucket access) but nothing
*enforced* them — a future config change could silently regress any of it,
and there was no way to know until a `terraform apply` against real
infrastructure. `Governance/security.yml` and `Docs/Security-Standards.md`
existed as empty placeholder files. The original review of this repo (see
project history) also found the Cloud SQL module never created the
`google_sql_user` resources it computed — fixed in
`modules/database/cloudsql/main.tf` as part of this rebuild.

## Known gaps — read before calling this "secure"

- Every `SEC_*` rule above is checked against `deployment.yaml`, never
  against what's actually running in GCP. There is no drift detection for
  most of them — if someone changes a firewall rule by hand in the
  console, this engine has no way to know. `modules/security
  /org_policies` is the one deliberate exception: those five constraints
  are enforced by GCP itself on every API call, console included, not
  just checked pre-deploy — see "Org policy constraints" above.
- `engine/secret_scanner.py` (`python -m engine.cli secret-scan .`, wired
  into both `.github/workflows/plan.yml` and `apply.yml`) covers
  high-confidence patterns only — PEM key blocks, a GCP SA key's real
  shape, AWS access key IDs, Slack tokens — see "Secret scanning" above.
  It does not do generic entropy-based "looks secret-ish" detection, so a
  genuinely novel credential format could still slip through; a tool like
  `gitleaks` would add broader (and noisier) coverage if that trade-off
  is worth it for this org.
- `SEC_OVERPRIVILEGED_SERVICE_ACCOUNT` is a WARNING, not an ERROR, and its
  role-name matching (`endswith(".admin")`) is a heuristic, not an
  authoritative list of "too broad" GCP roles.
- Binary Authorization's admission policy only takes effect on clusters
  that opt in (`enable_binary_authorization`, wired automatically from
  `resources.binary_authorization.enabled`) — it does not retroactively
  affect images already running, only new deployments.
- IAP tunnel access (`modules/security/iap`) is only as safe as the
  `members` list in `deployment.yaml` — this platform validates that the
  reference (`target_vm`) resolves to a real instance, not that the
  principals granted access are the right ones. That judgment call stays
  with whoever edits the config.
