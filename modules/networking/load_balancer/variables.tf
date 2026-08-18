variable "project_id" {

  type = string

}

variable "config" {

  type = any

}

variable "cloudrun_services" {

  type = map(string)

  default = {}

}