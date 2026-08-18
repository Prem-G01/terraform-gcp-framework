output "routers" {

  value = {

    for k, v in google_compute_router.router :

    k => v.name

  }

}



output "self_links" {

  value = {

    for k, v in google_compute_router.router :

    k => v.self_link

  }

}