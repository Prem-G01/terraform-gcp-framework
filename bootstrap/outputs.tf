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

output "git_clone_url" {
  description = "HTTPS clone URL for the central repository — see docs/service-accounts.md for the push-authentication setup."
  value       = var.create_git_repository ? google_secure_source_manager_repository.platform[0].uris[0].git_https : null
}

output "git_browse_url" {
  value = var.create_git_repository ? google_secure_source_manager_repository.platform[0].uris[0].html : null
}

output "git_push_sa_email" {
  value = var.create_git_repository ? google_service_account.git_push[0].email : null
}
