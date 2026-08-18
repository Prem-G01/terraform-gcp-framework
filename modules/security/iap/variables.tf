variable "project_id" {
  type = string
}

variable "config" {
  description = "resources.iap.instances from deployment.yaml — see modules/security/iap/main.tf for the expected shape."
  type        = any
}

variable "vm_names" {
  description = "instance name output from modules/compute/vm — used to resolve config[*].target_vm to a real instance name."
  type        = map(string)
  default     = {}
}

variable "vm_zones" {
  description = "zone output from modules/compute/vm — used to resolve config[*].target_vm to the instance's real zone."
  type        = map(string)
  default     = {}
}
