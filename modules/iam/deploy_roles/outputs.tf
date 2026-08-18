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
  apply_sa_roles = [
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/cloudkms.admin",
    "roles/run.admin",
    "roles/pubsub.admin",
    "roles/cloudtasks.enqueuer",
    "roles/cloudscheduler.admin",
    "roles/workflows.admin",
    "roles/artifactregistry.admin",
    "roles/monitoring.admin",
    "roles/logging.admin",
    "roles/bigquery.admin",
    "roles/serviceusage.serviceUsageAdmin",
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
