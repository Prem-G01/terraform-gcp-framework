output "state_bucket" {
  value = google_storage_bucket.state.name
}

output "artifact_bucket" {
  value = google_storage_bucket.artifacts.name
}

output "terraform_plan_sa_email" {
  value = google_service_account.terraform_plan.email
}

output "terraform_apply_sa_email" {
  value = google_service_account.terraform_apply.email
}

output "workload_identity_provider" {
  value = var.enable_workload_identity_federation ? google_iam_workload_identity_pool_provider.github[0].name : null
}
