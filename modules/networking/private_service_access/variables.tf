variable "project_id" {

  description = "GCP Project ID"

  type = string

}



variable "config" {

  description = "Private Service Access configuration"

  type = any

}



variable "networks" {

  description = "VPC self links"

  type = map(string)

}