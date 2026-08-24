resource "google_storage_bucket" "bucket" {

  for_each = var.config.buckets

  project = var.project_id

  name = each.value.name

  location = each.value.location

  storage_class = each.value.storage_class

  force_destroy = each.value.force_destroy

  # Secure-by-default fallbacks matching config/global/defaults.yaml
  # security_defaults.storage — that file is NOT actually read here (no
  # module in this platform reads security_defaults.yaml directly; see
  # docs/security.md), so these literals are this module's own copy of
  # the same values, not a live reference. Found missing entirely (every
  # field a hard-required each.value.X reference, no fallback at all)
  # while auditing for the same class of gap as the deletion_protection
  # fix in modules/compute/cloudrun — every environment's config
  # currently happens to set these explicitly, which is exactly why this
  # had gone unnoticed.
  uniform_bucket_level_access = lookup(each.value, "uniform_bucket_level_access", true)

  public_access_prevention = lookup(each.value, "public_access_prevention", "enforced")

  labels = each.value.labels

  versioning {

    enabled = try(each.value.versioning.enabled, true)

  }

  dynamic "lifecycle_rule" {

    for_each = each.value.lifecycle.enabled ? [1] : []

    content {

      condition {

        age = each.value.lifecycle.age

      }

      action {

        type = each.value.lifecycle.action

      }

    }

  }

}