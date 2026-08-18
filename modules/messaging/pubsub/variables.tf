variable "project_id" {

  type = string

}

variable "config" {

  type = any

}

variable "kms_keys" {

  type = map(string)

  default = {}

}