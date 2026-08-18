output "perimeter_names" {
  value = { for k, v in google_access_context_manager_service_perimeter.perimeter : k => v.name }
}

output "access_policy_id" {
  value = local.access_policy_id
}
