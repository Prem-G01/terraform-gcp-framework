output "nats" {

  value = {

    for k, v in google_compute_router_nat.nat :

    k => v.name

  }

}