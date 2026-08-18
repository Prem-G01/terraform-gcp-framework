resource "random_password" "passwords" {
  for_each = var.config.secrets
  length   = each.value.length
  special  = each.value.special
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = var.config.secrets
  project   = var.project_id
  secret_id = each.value.secret_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "versions" {
  for_each = var.config.secrets
  secret = google_secret_manager_secret.secrets[
    each.key
  ].id

  secret_data = random_password.passwords[
    each.key
  ].result

}