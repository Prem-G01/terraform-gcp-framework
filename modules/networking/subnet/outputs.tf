output "names" {

  description = "Subnet names"

  value = {

    for k, v in google_compute_subnetwork.subnet :

    k => v.name

  }

}


output "self_links" {

  description = "Subnet self links"

  value = {

    for k, v in google_compute_subnetwork.subnet :

    k => v.self_link

  }

}