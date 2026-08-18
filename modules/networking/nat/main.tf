resource "google_compute_router_nat" "nat" {

  for_each = var.config.nats



  project = var.project_id



  name = each.key



  region = each.value.region



  router = var.routers[

    each.value.router

  ]



  nat_ip_allocate_option = lookup(

    each.value,

    "nat_ip_allocate_option",

    "AUTO_ONLY"

  )



  source_subnetwork_ip_ranges_to_nat = lookup(

    each.value,

    "source_subnetwork_ip_ranges_to_nat",

    "ALL_SUBNETWORKS_ALL_IP_RANGES"

  )



  enable_endpoint_independent_mapping = lookup(

    each.value,

    "enable_endpoint_independent_mapping",

    true

  )



  min_ports_per_vm = lookup(

    each.value,

    "min_ports_per_vm",

    64

  )



  log_config {

    enable = lookup(

      each.value.log_config,

      "enable",

      true

    )



    filter = lookup(

      each.value.log_config,

      "filter",

      "ALL"

    )

  }

}