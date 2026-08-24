variable "organization" {

  type = any

}



variable "naming" {

  type = any

}

variable "environment" {

  description = "Environment name, from deployment.yaml metadata.environment — substituted into the {environment} token of naming.yaml's pattern templates."

  type = string

}

variable "instance_keys" {

  description = "Map of pattern key (must match a key in naming.yaml's naming.pattern, e.g. \"vm\", \"sql\") to the list of instance keys needing a generated name under that pattern."

  type = map(list(string))

  default = {}

}