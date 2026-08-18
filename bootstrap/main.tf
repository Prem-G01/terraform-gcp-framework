# =============================================================================
# Bootstrap — run ONCE per project, manually, before any environment stack
# can use a remote backend. See docs/state-management.md.
#
# NOT applied as part of this rebuild (kept code-only per the decision
# recorded in docs/troubleshooting.md "What this rebuild did not do") — a
# human with org-level IAM permissions runs `terraform apply` here
# deliberately, reviews the plan, and records the resulting bucket names
# and service-account emails in each environments/<env>/versions.tf
# backend-config comment.
# =============================================================================

locals {
  required_apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "securesourcemanager.googleapis.com",
  ]

  # Curated least-privilege role set for the apply SA — every service this
  # platform's modules/ actually create resources in, nothing broader
  # (specifically NOT roles/editor or roles/owner — see docs/security.md
  # SEC_OVERPRIVILEGED_SERVICE_ACCOUNT, which this list exists to satisfy).
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

  # Plan-time SA only ever reads — Cloud Build's "Validation" + "Plan"
  # steps run as this identity, never as the apply SA (see docs/cicd.md).
  plan_sa_roles = [
    "roles/viewer",
    "roles/iam.securityReviewer",
  ]
}

resource "google_project_service" "bootstrap_apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Remote state bucket ----------------------------------------------------

resource "google_storage_bucket" "state" {
  project  = var.project_id
  name     = var.state_bucket_name
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions         = 1
      days_since_noncurrent_time = var.state_bucket_retention_days
    }
    action {
      type = "Delete"
    }
  }

  soft_delete_policy {
    retention_duration_seconds = 7 * 24 * 60 * 60
  }

  depends_on = [google_project_service.bootstrap_apis]
}

# --- CI/CD artifact bucket (validation.json / plan.json / plan.txt) --------

resource "google_storage_bucket" "artifacts" {
  project  = var.project_id
  name     = var.artifact_bucket_name
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  lifecycle_rule {
    condition {
      age = 180
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.bootstrap_apis]
}

# --- CI/CD service accounts --------------------------------------------------

resource "google_service_account" "terraform_plan" {
  project      = var.project_id
  account_id   = "tf-plan"
  display_name = "Terraform Plan (read-only)"
  description  = "Runs `terraform plan` in CI/CD. Never has write access — see docs/service-accounts.md."

  depends_on = [google_project_service.bootstrap_apis]
}

resource "google_service_account" "terraform_apply" {
  project      = var.project_id
  account_id   = "tf-apply"
  display_name = "Terraform Apply"
  description  = "Runs `terraform apply` in CI/CD after manual approval — see docs/cicd.md."

  depends_on = [google_project_service.bootstrap_apis]
}

resource "google_project_iam_member" "plan_roles" {
  for_each = toset(local.plan_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_project_iam_member" "apply_roles" {
  for_each = toset(local.apply_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_apply.email}"
}

resource "google_storage_bucket_iam_member" "plan_reads_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_storage_bucket_iam_member" "apply_manages_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_apply.email}"
}

resource "google_storage_bucket_iam_member" "plan_writes_artifacts" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_storage_bucket_iam_member" "apply_writes_artifacts" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_apply.email}"
}

# --- Central Git repository (Secure Source Manager) ------------------------
# Google's current GCP-hosted git product — Cloud Source Repositories has
# not accepted new customers since 2024-06-17, see docs/service-accounts.md
# "Central repository". Public endpoint by default (var.git_instance_is_private
# = false) — Cloud Build and engineers push over the internet, authenticated
# by IAM, no VPC/Private Service Connect networking required.

resource "google_secure_source_manager_instance" "platform" {
  count = var.create_git_repository ? 1 : 0

  project     = var.project_id
  instance_id = var.git_instance_id
  location    = var.git_location

  private_config {
    is_private = var.git_instance_is_private
  }

  depends_on = [google_project_service.bootstrap_apis]
}

resource "google_secure_source_manager_repository" "platform" {
  count = var.create_git_repository ? 1 : 0

  project       = var.project_id
  repository_id = var.git_repository_id
  instance      = google_secure_source_manager_instance.platform[0].name
  location      = var.git_location
  description   = "Central repository for this platform — YAML-driven GCP Terraform framework."

  initial_config {
    default_branch = "main"
    # No gitignores/license/readme templates — this repo already has real
    # content to push, not an empty starter.
  }
}

# Dedicated identity for pushing/pulling — deliberately separate from
# tf-plan/tf-apply (those exist to run Terraform against GCP, not to hold
# git credentials; keeping them apart means a compromised git-push identity
# can't touch infrastructure, and vice versa).
resource "google_service_account" "git_push" {
  count = var.create_git_repository ? 1 : 0

  project      = var.project_id
  account_id   = "git-push"
  display_name = "CI/CD Git Push"
  description  = "Pushes to the central Secure Source Manager repository — e.g. a pipeline step that commits generated files back. See docs/service-accounts.md."

  depends_on = [google_project_service.bootstrap_apis]
}

resource "google_secure_source_manager_repository_iam_member" "git_push_writer" {
  count = var.create_git_repository ? 1 : 0

  project       = var.project_id
  location      = var.git_location
  repository_id = google_secure_source_manager_repository.platform[0].repository_id
  role          = "roles/securesourcemanager.repoWriter"
  member        = "serviceAccount:${google_service_account.git_push[0].email}"
}

# --- Workload Identity Federation (optional, off by default) --------------
# Avoids a long-lived service-account JSON key for CI/CD, per docs/service-
# accounts.md. Requires var.github_repository ("<org>/<repo>") when enabled.

resource "google_iam_workload_identity_pool" "cicd" {
  count = var.enable_workload_identity_federation ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = "cicd-pool"
  display_name              = "CI/CD"
  description               = "Federated identity for the Terraform plan/apply service accounts — no SA keys."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count = var.enable_workload_identity_federation ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.cicd[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "apply_wif_binding" {
  count = var.enable_workload_identity_federation ? 1 : 0

  service_account_id = google_service_account.terraform_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.cicd[0].name}/attribute.repository/${var.github_repository}"
}

resource "google_service_account_iam_member" "plan_wif_binding" {
  count = var.enable_workload_identity_federation ? 1 : 0

  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.cicd[0].name}/attribute.repository/${var.github_repository}"
}
