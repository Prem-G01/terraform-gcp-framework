output "cluster_names" {
  value = { for k, v in google_container_cluster.cluster : k => v.name }
}

output "endpoints" {
  description = "Cluster API endpoints. Not marked sensitive — reachability still depends on private_cluster_config; treat as topology info, not a secret."
  value       = { for k, v in google_container_cluster.cluster : k => v.endpoint }
}

output "ca_certificates" {
  value     = { for k, v in google_container_cluster.cluster : k => v.master_auth[0].cluster_ca_certificate }
  sensitive = true
}
