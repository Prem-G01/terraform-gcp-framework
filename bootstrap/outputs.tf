output "state_bucket" {
  value = google_storage_bucket.state.name
}

output "artifact_bucket" {
  value = google_storage_bucket.artifacts.name
}

output "log_bucket" {
  value = google_storage_bucket.logs.name
}

output "terraform_plan_sa_emails" {
  description = "Map of environment name to that environment's dedicated tf-plan SA email."
  value       = { for env, sa in google_service_account.terraform_plan : env => sa.email }
}

output "terraform_apply_sa_emails" {
  description = "Map of environment name to that environment's dedicated tf-apply SA email."
  value       = { for env, sa in google_service_account.terraform_apply : env => sa.email }
}

output "home_environment_sink_writer_identity" {
  description = "writer_identity of var.home_environment's log sink — only relevant if you're wiring up another environment's grants stack and want to compare formats; every other environment's writer_identity comes from that environment's own bootstrap/grants/ apply output."
  value       = google_logging_project_sink.home_environment.writer_identity
}

output "workload_identity_provider" {
  value = var.enable_workload_identity_federation ? google_iam_workload_identity_pool_provider.github[0].name : null
}
