variable "project_id" {

  type = string

}

variable "config" {

  type = any

}

variable "vpcs" {

  type = map(string)

}

variable "passwords" {

  description = "Passwords from Secret Manager"

  type = map(string)

}

variable "generated_names" {

  description = "Map of instance key to a naming.yaml pattern.sql-generated name (modules/shared/naming), used when an instance doesn't set an explicit `name`."

  type = map(string)

  default = {}

}