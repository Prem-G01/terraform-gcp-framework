# Zero-resource module — the single source of truth for the curated
# least-privilege role lists granted to this platform's deploy identities.
# Both bootstrap/main.tf (roles in the identities' home project) and
# bootstrap/grants/main.tf (the same roles granted in each spoke project)
# reference this module instead of maintaining two copies that could drift
# apart — see docs/service-accounts.md.

locals {
  # Every service this platform's modules/ actually creates resources in,
  # nothing broader (specifically NOT roles/editor or roles/owner — see
  # config/global/security.yaml SEC_OVERPRIVILEGED_SERVICE_ACCOUNT, which
  # this list exists to satisfy).
  #
  # 9 real gaps fixed here, plus one (orgpolicy) that turned out to need
  # a fundamentally different fix — found auditing this 2026-08-24,
  # verified directly against the installed IAM role definitions
  # (`gcloud iam roles describe`/`gcloud iam roles list`) against every
  # distinct `resource "google_*"` type across modules/, and against a
  # real apply where relevant — not assumed. None of this was ever
  # caught because every real apply this platform has done used a human
  # operator's own ADC credentials directly, never the real
  # tf-apply-<env> identity via WIF:
  #
  # - roles/compute.admin has ZERO container.* permissions (GKE is a
  #   separate API) — modules/compute/gke could never actually create a
  #   cluster or node pool under this identity. Added
  #   roles/container.admin.
  # - roles/cloudtasks.enqueuer only grants cloudtasks.tasks.create
  #   (runtime task enqueuing); none of the cloudtasks.queues.*
  #   permissions modules/messaging/cloudtasks needs to create/update/
  #   delete a queue. Replaced with roles/cloudtasks.admin.
  # - Six resource types had NO matching role in this list at all:
  #   modules/database/memorystore (roles/redis.admin),
  #   modules/networking/private_service_access
  #   (roles/servicenetworking.networksAdmin),
  #   modules/security/vpc_service_controls
  #   (roles/accesscontextmanager.policyAdmin),
  #   modules/security/binary_authorization
  #   (roles/binaryauthorization.policyAdmin),
  #   modules/compute/cloudfunctions (roles/cloudfunctions.admin),
  #   modules/ai/documentai (roles/documentai.admin).
  # - roles/resourcemanager.projectIamAdmin has ZERO iap.* permissions;
  #   modules/security/iap's google_iap_tunnel_instance_iam_member needs
  #   iap.tunnelInstances.setIamPolicy. Added roles/iap.admin.
  # - roles/orgpolicy.policyAdmin was added here on 2026-08-24 (same
  #   reasoning as above), but a REAL apply against prj-dg-devops-test-sit
  #   the same day proved it wrong: GCP rejects binding this specific
  #   predefined role at project scope outright — "Error 400: Role
  #   roles/orgpolicy.policyAdmin is not supported for this resource" —
  #   even though `gcloud iam list-testable-permissions` confirms the
  #   underlying orgpolicy.policies.create/update/delete permissions ARE
  #   testable at project scope. Verified this isn't project-specific:
  #   the same permissions ARE listed as testable at folder scope too, so
  #   the fix is a folder- or org-level `google_folder_iam_member`/
  #   `google_organization_iam_member` binding, not anything this
  #   project-scoped list can express. Removed from here — see
  #   docs/service-accounts.md "Org Policy grants need folder/org scope"
  #   for what actually needs to change, still unimplemented. This is
  #   very likely the real, previously-undiagnosed root cause of
  #   org_policies being blocked under a human operator's own credentials
  #   all session too, not merely a missing grant at whatever scope was
  #   assumed.
  apply_sa_roles = [
    "roles/compute.admin",
    "roles/container.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/cloudkms.admin",
    "roles/run.admin",
    "roles/pubsub.admin",
    "roles/cloudtasks.admin",
    "roles/cloudscheduler.admin",
    "roles/workflows.admin",
    "roles/artifactregistry.admin",
    "roles/monitoring.admin",
    "roles/logging.admin",
    "roles/bigquery.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/redis.admin",
    "roles/servicenetworking.networksAdmin",
    "roles/accesscontextmanager.policyAdmin",
    "roles/binaryauthorization.policyAdmin",
    "roles/cloudfunctions.admin",
    "roles/documentai.admin",
    "roles/iap.admin",
  ]

  # Plan-time identities only ever read.
  plan_sa_roles = [
    "roles/viewer",
    "roles/iam.securityReviewer",
  ]
}

output "apply_sa_roles" {
  value = local.apply_sa_roles
}

output "plan_sa_roles" {
  value = local.plan_sa_roles
}
