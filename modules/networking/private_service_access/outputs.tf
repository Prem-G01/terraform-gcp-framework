output "reserved_ranges" {

  value = {

    for k, v in google_compute_global_address.private_ip :

    k => v.name

  }

}



output "connections" {

  value = {

    for k, v in google_service_networking_connection.private_connection :

    k => v.peering

  }

}