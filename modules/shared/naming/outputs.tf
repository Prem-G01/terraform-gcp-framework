output "separator" {

  value = local.separator

}



output "company" {

  value = local.company

}

output "generated_names" {

  description = "Map of pattern key to (instance key => generated name), one entry per key requested in var.instance_keys."

  value = local.generated_names

}