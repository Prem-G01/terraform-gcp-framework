resource "google_compute_global_address" "private_ip" {

  for_each = var.config.private_service_access



  project = var.project_id



  name = each.value.address.name



  purpose = each.value.address.purpose



  address_type = each.value.address.address_type



  prefix_length = each.value.address.prefix_length



  network = var.networks[

    each.value.network

  ]

}



resource "google_service_networking_connection" "private_connection" {

  for_each = var.config.private_service_access



  network = var.networks[

    each.value.network

  ]



  service = each.value.service



  reserved_peering_ranges = [

    google_compute_global_address.private_ip[

      each.key

    ].name

  ]



  depends_on = [

    google_compute_global_address.private_ip

  ]

}