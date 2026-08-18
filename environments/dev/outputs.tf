output "enabled_resources" {
  value = module.platform.enabled_resources
}

output "vpc_self_links" {
  value = module.platform.vpc_self_links
}

output "cloudsql_private_ips" {
  value = module.platform.cloudsql_private_ips
}

output "cloudrun_urls" {
  value = module.platform.cloudrun_urls
}

output "load_balancer_ip_addresses" {
  value = module.platform.load_balancer_ip_addresses
}
