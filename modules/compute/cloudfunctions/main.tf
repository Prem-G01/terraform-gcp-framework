# 2nd-gen Cloud Functions. Source is a pre-uploaded object (bucket/object)
# rather than a `source_dir` this module zips itself — packaging and
# uploading function source is a CI build-step concern (see
# docs/cicd.md), not something a reusable Terraform module should own.

resource "google_cloudfunctions2_function" "function" {
  for_each = var.config.cloudfunctions

  project  = var.project_id
  name     = lookup(each.value, "name", each.key)
  location = each.value.location

  build_config {
    runtime     = each.value.runtime
    entry_point = each.value.entry_point

    source {
      storage_source {
        bucket = each.value.source.bucket
        object = each.value.source.object
      }
    }
  }

  service_config {
    max_instance_count = lookup(each.value.scaling, "max_instance_count", 3)
    min_instance_count = lookup(each.value.scaling, "min_instance_count", 0)

    available_memory = lookup(each.value.resources, "memory", "256M")
    timeout_seconds  = lookup(each.value.resources, "timeout_seconds", 60)

    service_account_email = var.service_accounts[each.value.service_account.name]

    # Deny-by-default ingress — flip to ALLOW_ALL per-instance only for
    # functions that genuinely need a public endpoint (e.g. a webhook).
    # engine/security_engine.py SEC_CLOUDFUNCTION_PUBLIC_INGRESS flags
    # every instance that does, as a WARNING (not an ERROR — unlike a
    # public VM/bucket/SQL instance, a public function is a legitimate,
    # common pattern).
    ingress_settings = lookup(each.value, "ingress_settings", "ALLOW_INTERNAL_ONLY")

    environment_variables = lookup(each.value, "env", {})
  }
}
