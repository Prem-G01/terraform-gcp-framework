variable "project_id" {
  type = string
}

variable "config" {
  type = any
}

variable "subnets" {
  type = map(string)
}

variable "service_accounts" {
  type = map(string)
}

variable "generated_names" {
  description = "Map of instance key to a naming.yaml pattern.vm-generated name (modules/shared/naming), used when an instance doesn't set an explicit `name`."
  type        = map(string)
  default     = {}
}