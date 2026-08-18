output "names" {
  value = {
    for k, v in google_compute_instance.vm :
    k => v.name
  }
}

output "internal_ips" {
  value = {
    for k, v in google_compute_instance.vm :
    k => v.network_interface[0].network_ip
  }
}