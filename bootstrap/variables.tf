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
