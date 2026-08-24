# Regression test for the real gap a security_defaults audit found
# (2026-08-19, see docs/security.md): uniform_bucket_level_access,
# public_access_prevention, and versioning.enabled were hard-required
# each.value.field references with zero fallback — safe only because
# every real environment's config happened to set them explicitly.
#
# Run: cd modules/storage/buckets && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_security_fields_fall_back_to_secure_defaults" {
  command = plan

  variables {
    config = {
      buckets = {
        test-bucket = {
          name          = "prj-dg-devops-test-dev-test-bucket"
          location      = "ASIA-SOUTH1"
          storage_class = "STANDARD"
          force_destroy = false
          labels        = {}
          lifecycle     = { enabled = false, age = 30, action = "Delete" }
          # uniform_bucket_level_access, public_access_prevention, and
          # versioning are deliberately omitted here.
        }
      }
    }
  }

  assert {
    condition     = google_storage_bucket.bucket["test-bucket"].uniform_bucket_level_access == true
    error_message = "uniform_bucket_level_access must default to true when omitted from config"
  }

  assert {
    condition     = google_storage_bucket.bucket["test-bucket"].public_access_prevention == "enforced"
    error_message = "public_access_prevention must default to \"enforced\" when omitted from config"
  }

  assert {
    condition     = google_storage_bucket.bucket["test-bucket"].versioning[0].enabled == true
    error_message = "versioning.enabled must default to true when omitted from config"
  }
}

run "explicit_security_fields_are_never_overridden" {
  command = plan

  variables {
    config = {
      buckets = {
        test-bucket = {
          name                        = "prj-dg-devops-test-dev-test-bucket"
          location                    = "ASIA-SOUTH1"
          storage_class               = "STANDARD"
          force_destroy               = false
          uniform_bucket_level_access = false
          public_access_prevention    = "inherited"
          versioning                  = { enabled = false }
          labels                      = {}
          lifecycle                   = { enabled = false, age = 30, action = "Delete" }
        }
      }
    }
  }

  assert {
    condition     = google_storage_bucket.bucket["test-bucket"].uniform_bucket_level_access == false
    error_message = "an explicit false must never be silently upgraded to the secure default"
  }

  assert {
    condition     = google_storage_bucket.bucket["test-bucket"].public_access_prevention == "inherited"
    error_message = "an explicit override must never be silently replaced by the secure default"
  }
}
