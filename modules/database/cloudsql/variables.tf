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