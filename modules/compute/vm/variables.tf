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