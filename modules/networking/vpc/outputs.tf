output "vpc_ids" {

  value = {

    for k, v in google_compute_network.vpc :

    k => v.id

  }

}



output "vpc_names" {

  value = {

    for k, v in google_compute_network.vpc :

    k => v.name

  }

}



output "self_links" {

  value = {

    for k, v in google_compute_network.vpc :

    k => v.self_link

  }

}