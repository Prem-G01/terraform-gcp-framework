# =============================================================================
# Grants — run ONCE per spoke project (any environment other than
# bootstrap's var.home_environment), by a human with IAM admin on that
# project. Grants the environment's already-existing tf-plan-<env>/
# tf-apply-<env> service accounts (created centrally by bootstrap/main.tf,
# in central_project_id) the same curated roles bootstrap grants its home
# environment — but here, in this project. Identity stays central,
# permissions are local to whoever owns each spoke project. See
# docs/service-accounts.md "Cross-project access".
#
# Optionally also creates this project's Cloud Logging sink to the central
# log bucket. Its writer_identity is only known after this apply — copy it
# into bootstrap's var.log_sink_writer_identities and re-apply bootstrap/
# to finish wiring centralized logging for this environment (see
# docs/logging.md "Centralized logging").
# =============================================================================

module "deploy_roles" {
  source = "../../modules/iam/deploy_roles"
}

provider "google" {
  project = var.spoke_project_id
  region  = var.region

  # See environments/dev/provider.tf for why these two lines are needed
  # — a human running this via Application Default Credentials otherwise
  # hits real quota-project errors on some APIs.
  user_project_override = true
  billing_project       = var.spoke_project_id
}

locals {
  plan_sa_email  = "tf-plan-${var.environment}@${var.central_project_id}.iam.gserviceaccount.com"
  apply_sa_email = "tf-apply-${var.environment}@${var.central_project_id}.iam.gserviceaccount.com"
}

resource "google_project_service" "logging" {
  count = var.create_log_sink ? 1 : 0

  project            = var.spoke_project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "plan_roles" {
  for_each = toset(module.deploy_roles.plan_sa_roles)

  project = var.spoke_project_id
  role    = each.value
  member  = "serviceAccount:${local.plan_sa_email}"
}

resource "google_project_iam_member" "apply_roles" {
  for_each = toset(module.deploy_roles.apply_sa_roles)

  project = var.spoke_project_id
  role    = each.value
  member  = "serviceAccount:${local.apply_sa_email}"
}

resource "google_logging_project_sink" "central_log_export" {
  count = var.create_log_sink ? 1 : 0

  project                = var.spoke_project_id
  name                   = "central-log-export-${var.environment}"
  destination            = "storage.googleapis.com/${var.central_log_bucket}"
  filter                 = var.log_filter
  unique_writer_identity = true

  depends_on = [google_project_service.logging]
}
