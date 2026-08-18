variable "project_id" {
  type = string
}

variable "config" {
  type = any
}

variable "organization_id" {
  description = "Required only when create_access_policy is true."
  type        = string
  default     = ""
}

variable "create_access_policy" {
  description = <<-EOT
    google_access_context_manager_access_policy is a SINGLETON per GCP
    organization — creating a second one when one already exists fails.
    Leave this false (default) and set existing_access_policy_id to the
    org's real policy in every case except bootstrapping a brand-new org
    that has never had one. See docs/security.md "VPC Service Controls —
    read before enabling."
  EOT
  type        = bool
  default     = false
}

variable "policy_title" {
  type    = string
  default = "Organization Access Policy"
}

variable "existing_access_policy_id" {
  description = "Numeric id of the org's existing access policy (gcloud access-context-manager policies list). Required when create_access_policy is false and any perimeter is enabled."
  type        = string
  default     = ""
}
