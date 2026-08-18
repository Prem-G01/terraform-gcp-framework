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

- Every rule above is checked against `deployment.yaml`, never against
  what's actually running in GCP. There is no drift detection — if someone
  changes a firewall rule by hand in the console, this engine has no way
  to know.
- No secret-scanning of the repository itself (e.g. a credential
  accidentally committed to a config file) — add a tool like `gitleaks` in
  CI if that's a real risk for this org.
- `SEC_OVERPRIVILEGED_SERVICE_ACCOUNT` is a WARNING, not an ERROR, and its
  role-name matching (`endswith(".admin")`) is a heuristic, not an
  authoritative list of "too broad" GCP roles.
