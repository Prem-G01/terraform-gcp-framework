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
    # `scaling`/`resources` were each hard-required each.value references
    # with no fallback for the whole object, even though every field
    # inside already had a lookup() default — same gap class found in
    # cloudsql/artifact_registry/scheduler/cloudtasks (2026-08-24). Every
    # real config sets both explicitly, which is why this went unnoticed.
    max_instance_count = lookup(lookup(each.value, "scaling", {}), "max_instance_count", 3)
    min_instance_count = lookup(lookup(each.value, "scaling", {}), "min_instance_count", 0)

    available_memory = lookup(lookup(each.value, "resources", {}), "memory", "256M")
    timeout_seconds  = lookup(lookup(each.value, "resources", {}), "timeout_seconds", 60)

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

# `ingress_settings` above only controls which *network paths* can reach
# this function — it grants no IAM authorization. This module had no
# invoker mechanism at all before this: even ALLOW_INTERNAL_ONLY still
# returns 403 to every caller, including a legitimate one inside the same
# VPC, until explicitly granted invoker access. Found 2026-08-25 by
# actually curling a real deployed function from inside its own VPC (via
# a real IAP-tunneled SSH session using the calling VM's own identity
# token) rather than just checking `terraform apply` succeeded.
# Deliberately a members list, not an `allow_unauthenticated` toggle like
# modules/compute/cloudrun — ALLOW_INTERNAL_ONLY functions should grant
# specific callers, never `allUsers`, or the network-level restriction
# becomes meaningless.
#
# Binds against the underlying Cloud Run service (google_cloud_run_v2
# _service_iam_member), NOT google_cloudfunctions2_function_iam_member —
# confirmed against real GCP 2026-08-25 that these are two separate ACLs:
# granting roles/cloudfunctions.invoker via the Cloud-Functions-specific
# IAM resource leaves the underlying Cloud Run service's own IAM policy
# completely empty (`gcloud run services get-iam-policy` showed zero
# bindings), and HTTP invocation is actually gated by the Cloud Run
# policy, not the Cloud Functions one. A gen2 function's underlying Cloud
# Run service shares its exact name.
locals {
  cloudfunctions_invoker_bindings = merge([
    for name, cfg in var.config.cloudfunctions : {
      for member in lookup(cfg, "invoker_members", []) :
      "${name}-${member}" => { function_name = name, member = member }
    }
  ]...)
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = local.cloudfunctions_invoker_bindings

  project  = var.project_id
  location = google_cloudfunctions2_function.function[each.value.function_name].location
  name     = google_cloudfunctions2_function.function[each.value.function_name].name
  role     = "roles/run.invoker"
  member   = each.value.member
}
