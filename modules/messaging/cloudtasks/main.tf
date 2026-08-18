resource "google_cloud_tasks_queue" "queue" {

  for_each = var.config.cloudtasks



  project = var.project_id



  name = lookup(each.value, "name", each.key)



  location = each.value.location



  rate_limits {

    max_dispatches_per_second = lookup(

      each.value.rate_limits,

      "max_dispatches_per_second",

      10

    )



    max_concurrent_dispatches = lookup(

      each.value.rate_limits,

      "max_concurrent_dispatches",

      20

    )

  }



  retry_config {

    max_attempts = lookup(

      each.value.retry_config,

      "max_attempts",

      5

    )



    min_backoff = lookup(

      each.value.retry_config,

      "min_backoff",

      "1s"

    )



    max_backoff = lookup(

      each.value.retry_config,

      "max_backoff",

      "60s"

    )



    max_doublings = lookup(

      each.value.retry_config,

      "max_doublings",

      5

    )



    max_retry_duration = lookup(

      each.value.retry_config,

      "max_retry_duration",

      "300s"

    )

  }



  stackdriver_logging_config {

    sampling_ratio = lookup(

      each.value.stackdriver_logging_config,

      "sampling_ratio",

      1.0

    )

  }

}