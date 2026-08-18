output "ip_addresses" {

  value = {

    for k, v in google_compute_global_address.ip :

    k => v.address

  }

}



output "forwarding_rules" {

  value = {

    for k, v in google_compute_global_forwarding_rule.forwarding_rule :

    k => v.id

  }

}