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

# REAL BUG FOUND AND FIXED (2026-08-18): `delete_default_routes_on_create`
# removes the VPC's 0.0.0.0/0 route to the default internet gateway — but
# Cloud NAT does NOT create that route itself; NAT only translates traffic
# that's already being routed to the internet gateway. Delete the default
# route and never replace it, and NAT is fully configured but completely
# unreachable — nothing has a path to the internet at all. This is the
# most likely root cause of the GKE node networking failure documented in
# docs/troubleshooting.md (nodes couldn't pull images: `dial tcp ... i/o
# timeout`) — dev-vpc has delete_default_routes_on_create: true and,
# before this fix, no module ever created a replacement route.
#
# Default: recreate the route whenever the default was deleted (matches
# what nearly every deployment actually wants — NAT should work). Set
# create_default_internet_route: false per-VPC only if you're deliberately
# routing all egress through something else (a hub-and-spoke NVA, Private
# Service Connect only, no internet egress at all, ...).
resource "google_compute_route" "default_internet_gateway" {
  for_each = {
    for k, v in var.config.vpcs : k => v
    if lookup(v, "delete_default_routes_on_create", true) && lookup(v, "create_default_internet_route", true)
  }

  project = var.project_id
  name    = "${each.key}-default-internet"
  network = google_compute_network.vpc[each.key].name

  dest_range       = "0.0.0.0/0" # hardcode-allow: the fixed "any destination" CIDR that defines a default route, not an environment-specific value
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}
