output "plan_sa_email" {
  value = local.plan_sa_email
}

output "apply_sa_email" {
  value = local.apply_sa_email
}

output "log_sink_writer_identity" {
  description = "Copy this into bootstrap's -var log_sink_writer_identities='{\"<env>\": \"<this value>\"}' (merged with any existing entries) and re-apply bootstrap/ to finish wiring this environment into centralized logging. null if create_log_sink was false."
  value       = var.create_log_sink ? google_logging_project_sink.central_log_export[0].writer_identity : null
}
