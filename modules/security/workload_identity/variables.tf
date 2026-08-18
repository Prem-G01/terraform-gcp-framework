variable "project_id" {
  type = string
}

variable "config" {
  description = "resources.workload_identity.instances from deployment.yaml — see modules/security/workload_identity/main.tf for the expected shape."
  type        = any
}

variable "service_account_ids" {
  description = "id output from modules/iam/service_accounts — used to resolve config[*].gcp_service_account to the real google_service_account.id that google_service_account_iam_member binds against."
  type        = map(string)
  default     = {}
}
