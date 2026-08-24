# Regression coverage for the deletion_protection default this rebuild
# added on 2026-08-19 (see docs/security.md) — the module previously had
# no `deletion_protection` argument at all, meaning Terraform silently
# used the provider's own default. Locks in that omitting it now defaults
# to false (a generated secret is trivially regeneratable, unlike this
# platform's usual true-by-default for cloudsql/gke/bigquery), and that an
# explicit true is never silently dropped back to that default.
#
# Run: cd modules/security/secrets && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_deletion_protection_defaults_to_false" {
  command = plan

  variables {
    config = {
      secrets = {
        api-key = {
          secret_id = "api-key"
          length    = 32
          special   = true
        }
      }
    }
  }

  assert {
    condition     = google_secret_manager_secret.secrets["api-key"].deletion_protection == false
    error_message = "deletion_protection should default to false when omitted — a generated secret is trivially regeneratable"
  }
}

run "explicit_deletion_protection_is_never_overridden" {
  command = plan

  variables {
    config = {
      secrets = {
        external-cert-key = {
          secret_id           = "external-cert-key"
          length              = 32
          special             = true
          deletion_protection = true
        }
      }
    }
  }

  assert {
    condition     = google_secret_manager_secret.secrets["external-cert-key"].deletion_protection == true
    error_message = "an explicit deletion_protection = true must never be silently overridden to false"
  }
}
