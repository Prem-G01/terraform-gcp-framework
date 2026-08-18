resource "google_compute_network" "vpc" {
  for_each = var.config.vpcs

  project = var.project_id
  name    = each.key

  description = lookup(each.value, "description", null)

  auto_create_subnetworks         = lookup(each.value, "auto_create_subnetworks", false)
  routing_mode                    = lookup(each.value, "routing_mode", "GLOBAL")
  mtu                             = lookup(each.value, "mtu", 1460)
  delete_default_routes_on_create = lookup(each.value, "delete_default_routes_on_create", true)
  enable_ula_internal_ipv6        = lookup(each.value, "enable_ula_internal_ipv6", false)
}
