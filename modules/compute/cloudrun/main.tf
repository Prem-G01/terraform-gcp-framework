resource "google_cloud_run_v2_service" "cloudrun" {
  for_each            = var.config.cloudrun
  project             = var.project_id
  name                = lookup(each.value, "name", each.key)
  location            = each.value.location
  ingress             = each.value.ingress
  deletion_protection = lookup(each.value, "deletion_protection", true)
  labels              = each.value.labels

  template {
    service_account = var.service_accounts[
      each.value.service_account.name
    ]

    scaling {
      min_instance_count = each.value.scaling.min_instance_count
      max_instance_count = each.value.scaling.max_instance_count
    }

    containers {
      image = format(
        "%s/%s:%s",
        each.value.image.repository,
        each.value.image.path,
        each.value.image.tag
      )

      resources {
        limits = {
          cpu    = each.value.resources.cpu
          memory = each.value.resources.memory
        }

      }
      dynamic "env" {

        for_each = each.value.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}