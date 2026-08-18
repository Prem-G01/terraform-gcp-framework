variable "project_id" {
  type = string
}

variable "config" {
  type = any
}

variable "vpcs" {
  type = map(string)
}

variable "subnets" {
  type = map(string)
}

variable "service_accounts" {
  type    = map(string)
  default = {}
}

variable "enable_binary_authorization" {
  description = "Whether every cluster this module creates enforces the project's Binary Authorization policy (modules/security/binary_authorization) — a project policy alone enforces nothing on GKE until each cluster opts in."
  type        = bool
  default     = false
}
