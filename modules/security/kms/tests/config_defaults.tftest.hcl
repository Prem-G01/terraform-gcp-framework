# Regression coverage for KMS's config-normalization defaults, which had
# no test at all before this — despite KMS being one of the highest-
# consequence modules in this platform (crypto_key has
# `lifecycle { prevent_destroy = true }`, and GCP itself has no API to
# hard-delete a key or keyring regardless — see docs/security.md).
#
# Locks in: rotation_period defaults to 90 days (7776000s), purpose
# defaults to ENCRYPT_DECRYPT, and a keyring's real GCP name falls back to
# its config map key — all `lookup(x, "field", default)` calls in
# modules/security/kms/main.tf that a config typo or omission could
# silently mis-set with no error, the same class of gap the 2026-08-19
# security_defaults audit found elsewhere (docs/security.md).
#
# Run: cd modules/security/kms && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_fields_fall_back_to_documented_defaults" {
  command = plan

  variables {
    config = {
      kms = {
        app-keyring = {
          location = "asia-south1"
          keys = {
            data-key = {}
          }
        }
      }
    }
  }

  assert {
    condition     = google_kms_key_ring.keyring["app-keyring"].name == "app-keyring"
    error_message = "keyring name should default to its config map key when `name` is omitted"
  }

  assert {
    condition     = google_kms_crypto_key.crypto_key["app-keyring-data-key"].purpose == "ENCRYPT_DECRYPT"
    error_message = "purpose should default to ENCRYPT_DECRYPT when omitted"
  }

  assert {
    condition     = google_kms_crypto_key.crypto_key["app-keyring-data-key"].rotation_period == "7776000s"
    error_message = "rotation_period should default to 7776000s (90 days) when omitted"
  }
}

run "explicit_fields_are_never_silently_overridden" {
  command = plan

  variables {
    config = {
      kms = {
        app-keyring = {
          name     = "app-keyring-real-name"
          location = "asia-south1"
          keys = {
            sign-key = {
              purpose = "ASYMMETRIC_SIGN"
            }
            short-rotation-key = {
              rotation_period = "2592000s"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = google_kms_key_ring.keyring["app-keyring"].name == "app-keyring-real-name"
    error_message = "an explicit keyring name must never be silently overridden by the config map key"
  }

  assert {
    condition     = google_kms_crypto_key.crypto_key["app-keyring-sign-key"].purpose == "ASYMMETRIC_SIGN"
    error_message = "an explicit purpose must never be silently overridden to ENCRYPT_DECRYPT"
  }

  assert {
    condition     = google_kms_crypto_key.crypto_key["app-keyring-short-rotation-key"].rotation_period == "2592000s"
    error_message = "an explicit rotation_period must never be silently overridden to the 90-day default"
  }
}
