resource "google_cloud_tasks_queue" "queue" {

  for_each = var.config.cloudtasks



  project = var.project_id



  name = lookup(each.value, "name", each.key)



  location = each.value.location



  # rate_limits/retry_config/stackdriver_logging_config were each a
  # hard-required each.value reference with no fallback for the whole
  # block, even though every field inside already had a lookup() default
  # — the same gap class found in modules/database/cloudsql (backup),
  # modules/artifact_registry (cleanup_policy), and
  # modules/orchestration/scheduler (retry_config). Every real config
  # sets all three explicitly, which is exactly why this went unnoticed.
  # Found 2026-08-24.

  rate_limits {

    max_dispatches_per_second = lookup(

      lookup(each.value, "rate_limits", {}),

      "max_dispatches_per_second",

      10

    )



    max_concurrent_dispatches = lookup(

      lookup(each.value, "rate_limits", {}),

      "max_concurrent_dispatches",

      20

    )

  }



  retry_config {

    max_attempts = lookup(

      lookup(each.value, "retry_config", {}),

      "max_attempts",

      5

    )



    min_backoff = lookup(

      lookup(each.value, "retry_config", {}),

      "min_backoff",

      "1s"

    )



    max_backoff = lookup(

      lookup(each.value, "retry_config", {}),

      "max_backoff",

      "60s"

    )



    max_doublings = lookup(

      lookup(each.value, "retry_config", {}),

      "max_doublings",

      5

    )



    max_retry_duration = lookup(

      lookup(each.value, "retry_config", {}),

      "max_retry_duration",

      "300s"

    )

  }



  stackdriver_logging_config {

    sampling_ratio = lookup(

      lookup(each.value, "stackdriver_logging_config", {}),

      "sampling_ratio",

      1.0

    )

  }

}