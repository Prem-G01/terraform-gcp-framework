variable "project_id" {
  type = string
}

variable "disable_service_account_key_creation" {
  description = "constraints/iam.disableServiceAccountKeyCreation — blocks creating a downloadable SA key JSON, org-policy-enforced rather than merely convention. This platform's own CI/CD identities never use keys (see docs/service-accounts.md), so this constraint costs nothing here and closes the door on anyone else doing it by hand."
  type        = bool
  default     = true
}

variable "restrict_vm_external_ips" {
  description = "constraints/compute.vmExternalIpAccess, denied for every VM — the project-level backstop behind SEC_PUBLIC_VM (config/global/security.yaml), which only catches a public IP if it's written into deployment.yaml. This blocks it even via direct console/gcloud."
  type        = bool
  default     = true
}

variable "restrict_public_sql_ips" {
  description = "constraints/sql.restrictPublicIp — the project-level backstop behind SEC_PUBLIC_SQL."
  type        = bool
  default     = true
}

variable "require_os_login" {
  description = "constraints/compute.requireOsLogin — the project-level backstop behind SEC_MISSING_OS_LOGIN. OS Login ties SSH access to IAM identity instead of static SSH keys in metadata."
  type        = bool
  default     = true
}

variable "skip_default_network_creation" {
  description = "constraints/compute.skipDefaultNetworkCreation — a new project normally gets an auto-mode \"default\" VPC with permissive default firewall rules. This platform always creates its own VPC/firewall explicitly (modules/networking/vpc, modules/networking/firewall); the default network is pure attack surface no config here ever intends to use."
  type        = bool
  default     = true
}
