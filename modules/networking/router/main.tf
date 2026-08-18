resource "google_compute_router" "router" {

  for_each = var.config.routers



  project = var.project_id



  name = each.key



  region = each.value.region



  network = var.vpcs[

    each.value.network

  ]



  description = lookup(

    each.value,

    "description",

    null

  )



  bgp {

    asn = each.value.bgp.asn



    advertise_mode = lookup(

      each.value.bgp,

      "advertise_mode",

      "DEFAULT"

    )

  }

}