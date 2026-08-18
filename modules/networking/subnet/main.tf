resource "google_compute_subnetwork" "subnet" {

  for_each = var.config.subnets
  project  = var.project_id
  name     = each.key
  region   = each.value.region
  network = var.vpcs[
    each.value.vpc
  ]


  ip_cidr_range = each.value.cidr
  description = lookup(
    each.value,
    "description",
    null
  )

  private_ip_google_access = lookup(
    each.value,
    "private_ip_google_access",
    true
  )


  purpose = lookup(
    each.value,
    "purpose",
    "PRIVATE"
  )

  role = lookup(
    each.value,
    "role",
    "ACTIVE"

  )



  dynamic "log_config" {

    for_each = lookup(

      each.value,

      "flow_logs",

      {}

    ).enabled ? [1] : []



    content {

      aggregation_interval = each.value.flow_logs.aggregation_interval
      flow_sampling        = each.value.flow_logs.flow_sampling
      metadata             = each.value.flow_logs.metadata

    }

  }

}