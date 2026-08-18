resource "google_storage_bucket" "bucket" {

  for_each = var.config.buckets

  project = var.project_id

  name = each.value.name

  location = each.value.location

  storage_class = each.value.storage_class

  force_destroy = each.value.force_destroy

  uniform_bucket_level_access = each.value.uniform_bucket_level_access

  public_access_prevention = each.value.public_access_prevention

  labels = each.value.labels

  versioning {

    enabled = each.value.versioning.enabled

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