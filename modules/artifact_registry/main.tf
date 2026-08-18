resource "google_artifact_registry_repository" "repository" {
  for_each               = var.config.artifact_registry
  project                = var.project_id
  repository_id          = each.value.repository_id
  format                 = each.value.format
  location               = each.value.location
  description            = each.value.description
  labels                 = lookup(each.value, "labels", {})
  cleanup_policy_dry_run = false
  dynamic "cleanup_policies" {
    for_each = each.value.cleanup_policy.enabled ? [1] : []
    content {
      id     = "keep-latest"
      action = "DELETE"
      condition {
        older_than = "30d"
      }
    }
  }
}