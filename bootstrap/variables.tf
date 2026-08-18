variable "project_id" {
  description = "Project that will host the state bucket, artifact bucket, and CI/CD service accounts. Can be a dedicated ops/platform project or the same project the platform deploys into."
  type        = string
}

variable "region" {
  type = string
  # A default here (unlike in modules/) is a deliberate convenience for a
  # stack a human runs once, by hand, with -var flags always available to
  # override it — see docs/state-management.md "Bootstrapping".
  default = "asia-south1" # hardcode-allow: manually-run bootstrap default, always overridable via -var
}

variable "state_bucket_name" {
  description = "Globally-unique GCS bucket name for Terraform remote state. No default — bucket names collide platform-wide, so this must be chosen deliberately per org, not inherited from a template value."
  type        = string
}

variable "artifact_bucket_name" {
  description = "Globally-unique GCS bucket name for validation.json / plan.json / plan.txt / metadata.json produced by CI/CD (see docs/logging.md)."
  type        = string
}

variable "state_bucket_retention_days" {
  description = "How long a noncurrent state object version is kept before GCS deletes it. Object versioning itself is always on (see main.tf) — this only bounds how far back you can roll back."
  type        = number
  default     = 90
}

variable "environments" {
  description = "Environment names this bootstrap grants the apply SA access to (used for per-environment IAM conditions, not for creating environment resources — bootstrap never touches environments/)."
  type        = list(string)
  default     = ["dev", "sit", "uat", "prod"]
}

variable "enable_workload_identity_federation" {
  description = "Create a Workload Identity Federation pool so CI/CD authenticates without a long-lived service-account key (see docs/service-accounts.md). Requires github_repository when true."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "\"<org>/<repo>\" allowed to assume the CI/CD service accounts via WIF. Required only when enable_workload_identity_federation is true."
  type        = string
  default     = ""
}

# --- Central Git repository (Secure Source Manager) ------------------------
# Cloud Source Repositories has not been available to new customers/orgs
# since 2024-06-17 — Secure Source Manager is Google's current GCP-hosted
# git replacement. See docs/service-accounts.md "Central repository" for
# why this project needed it instead of the older product.

variable "create_git_repository" {
  description = "Create a Secure Source Manager instance + repository as this platform's central, GCP-hosted git remote. A provisioned, billable instance — not a free API toggle like the old Cloud Source Repositories."
  type        = bool
  default     = true
}

variable "git_instance_id" {
  description = "Secure Source Manager instance id. Must be globally unique within the project, lowercase, starts with a letter."
  type        = string
  default     = "platform-git"
}

variable "git_repository_id" {
  description = "Repository id within the Secure Source Manager instance."
  type        = string
  default     = "terraform-gcp-framework"
}

variable "git_location" {
  description = <<-EOT
    Region for the Secure Source Manager instance. SSM has its own,
    smaller supported-region list than most GCP services — asia-south1
    (this platform's primary region) is NOT one of them as of 2026-08.
    Verified supported regions at that date: us-central1, us-east1,
    northamerica-northeast1, asia-east1, asia-northeast1, asia-northeast3,
    australia-southeast1, europe-west2, europe-west4, me-west1,
    me-central2 — re-verify at https://cloud.google.com/secure-source-manager/docs/locations
    before relying on this default, that list changes over time.
  EOT
  type        = string
  default     = "asia-east1" # hardcode-allow: manually-run bootstrap default, always overridable via -var — closest SSM-supported region to asia-south1, and already in config/global/regions.yaml's approved list
}

variable "git_instance_is_private" {
  description = "If true, the SSM instance's git/API endpoints are only reachable from within your VPC (needs Private Service Connect setup, not wired here). Default false — Cloud Build and engineers can push over the public internet, authenticated via IAM, no VPC networking required."
  type        = bool
  default     = false
}
