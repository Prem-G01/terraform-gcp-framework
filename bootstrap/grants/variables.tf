variable "spoke_project_id" {
  description = "The environment's own GCP project — where this stack actually creates resources. Distinct from var.central_project_id, which only hosts the tf-plan/tf-apply identities themselves."
  type        = string
}

variable "central_project_id" {
  description = "The project bootstrap/ was applied against — where var.environment's tf-plan-<env>/tf-apply-<env> service accounts actually live. Used only to compute their emails; this stack never creates or modifies anything there directly."
  type        = string
}

variable "environment" {
  description = "Which environment this spoke project belongs to (must be one of the entries in bootstrap's var.environments, and must NOT be bootstrap's var.home_environment — that one's roles are granted directly by bootstrap/main.tf, in central_project_id, since its project IS central_project_id)."
  type        = string
}

variable "region" {
  description = "Region this spoke project's own resources deploy into — must match this environment's deployment.yaml region for the naming/region engines to agree."
  type        = string
}

variable "create_log_sink" {
  description = "Create a Cloud Logging sink exporting this project's logs to the central log bucket in central_project_id. Set false if this environment's logs should stay local, or if you're not using centralized logging."
  type        = bool
  default     = true
}

variable "central_log_bucket" {
  description = "Name of the central log bucket (bootstrap's log_bucket output). Required when create_log_sink is true."
  type        = string
  default     = ""
}

variable "log_filter" {
  description = "Cloud Logging filter for what this project exports to the central bucket. Empty string exports every log entry."
  type        = string
  default     = ""
}
