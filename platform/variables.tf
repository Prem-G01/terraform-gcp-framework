# This module is intentionally the ONLY place resource logic lives. It is
# sourced identically by every environment's environments/<env>/main.tf —
# it has no idea whether it's being applied to dev or prod, and must stay
# that way (see docs/modules.md "Environment-agnostic by construction").

variable "project_id" {
  description = "GCP project ID this deployment targets. Comes from config/environments/<env>/deployment.yaml (project.id), never hardcoded."
  type        = string
}

variable "environment" {
  description = "Environment name, from deployment.yaml metadata.environment. Used only for labeling — never for branching resource logic."
  type        = string
}

variable "deployment_file" {
  description = <<-EOT
    Absolute path to a VALIDATED, NORMALIZED deployment JSON artifact —
    produced by `python -m engine.cli render`, never edited by hand and
    never the raw config/environments/<env>/deployment.yaml. Rendering
    refuses to write this file if validation found any ERROR-severity
    finding, which is what actually stops an invalid config from reaching
    `terraform plan` (see docs/validation.md).
  EOT
  type        = string
}
