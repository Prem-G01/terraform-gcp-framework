output "firewalls" {

  value = {

    for k, v in google_compute_firewall.firewall :

    k => v.name

  }

}