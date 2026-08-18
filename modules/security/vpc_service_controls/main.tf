# See docs/security.md "VPC Service Controls — read before enabling" before
# turning this on for any real project. A misconfigured perimeter can cut
# the project off from APIs (Storage, BigQuery, etc.) that every other
# module in this platform depends on — this is the one resource type here
# capable of breaking everything else at once.

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_access_context_manager_access_policy" "policy" {
  count = var.create_access_policy ? 1 : 0

  parent = "organizations/${var.organization_id}"
  title  = var.policy_title
}

locals {
  access_policy_id = var.create_access_policy ? google_access_context_manager_access_policy.policy[0].name : var.existing_access_policy_id
}

resource "google_access_context_manager_service_perimeter" "perimeter" {
  for_each = var.config.vpc_service_controls

  parent = "accessPolicies/${local.access_policy_id}"
  name   = "accessPolicies/${local.access_policy_id}/servicePerimeters/${lookup(each.value, "name", each.key)}"
  title  = lookup(each.value, "name", each.key)

  perimeter_type = lookup(each.value, "perimeter_type", "PERIMETER_TYPE_REGULAR")

  status {
    restricted_services = each.value.restricted_services
    resources           = ["projects/${data.google_project.current.number}"]
  }
}
