# Redis via Private Service Access only — same connection
# modules/networking/private_service_access already sets up for Cloud SQL
# (see config/global/dependencies.yaml memorystore.requires). No public
# IP mode is exposed by this module at all — not a config toggle to
# disable, there is no field for it.

resource "google_redis_instance" "cache" {
  for_each = var.config.memorystore

  project = var.project_id
  name    = lookup(each.value, "name", each.key)
  region  = each.value.region

  tier           = lookup(each.value, "tier", "BASIC")
  memory_size_gb = each.value.memory_size_gb
  redis_version  = lookup(each.value, "redis_version", "REDIS_7_2")

  authorized_network = var.vpcs[each.value.network]
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  auth_enabled            = lookup(each.value, "auth_enabled", true)
  transit_encryption_mode = lookup(each.value, "transit_encryption_mode", "SERVER_AUTHENTICATION")

  # Defaults to GCP's own native default (false) rather than this
  # platform's usual true-by-default for cloudsql/gke/bigquery/
  # workflows/cloudrun — a cache is normally rebuildable/ephemeral data,
  # not the kind of durable state those defaults exist to protect. Opt
  # in per-instance if this cache genuinely holds something
  # irreplaceable.
  deletion_protection = lookup(each.value, "deletion_protection", false)
}
