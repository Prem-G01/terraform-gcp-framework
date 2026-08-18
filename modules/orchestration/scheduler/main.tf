resource "google_cloud_scheduler_job" "job" {

  for_each = var.config.scheduler



  project = var.project_id



  name = lookup(each.value, "name", each.key)



  region = each.value.location



  schedule = each.value.schedule



  time_zone = lookup(

    each.value,

    "time_zone",

    "UTC"

  )



  retry_config {

    retry_count = lookup(

      each.value.retry_config,

      "retry_count",

      3

    )



    max_retry_duration = lookup(

      each.value.retry_config,

      "max_retry_duration",

      "300s"

    )



    min_backoff_duration = lookup(

      each.value.retry_config,

      "min_backoff_duration",

      "5s"

    )



    max_backoff_duration = lookup(

      each.value.retry_config,

      "max_backoff_duration",

      "60s"

    )



    max_doublings = lookup(

      each.value.retry_config,

      "max_doublings",

      5

    )

  }



  dynamic "http_target" {

    for_each = lookup(

      each.value,

      "http_target",

      {}

    ) != {} ? [1] : []



    content {

      uri = each.value.http_target.uri



      http_method = lookup(

        each.value.http_target,

        "http_method",

        "POST"

      )



      headers = lookup(

        each.value.http_target,

        "headers",

        {}

      )



      body = base64encode(

        lookup(

          each.value.http_target,

          "body",

          "{}"

        )

      )



      dynamic "oidc_token" {

        for_each = lookup(

          each.value.http_target,

          "oidc_token",

          {}

        ) != {} ? [1] : []



        content {

          service_account_email = lookup(

            each.value.http_target.oidc_token,

            "service_account_email",

            ""

          )

        }

      }

    }

  }

}