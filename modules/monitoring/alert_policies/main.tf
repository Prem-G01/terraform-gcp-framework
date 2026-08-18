resource "google_monitoring_alert_policy" "alerts" {

  for_each = var.config.alert_policies

  project = var.project_id

  display_name = each.value.display_name

  combiner = "OR"



  conditions {

    display_name = each.value.display_name



    condition_threshold {



      filter = trimspace(

        each.value.filter

      )



      duration = each.value.duration



      comparison = each.value.comparison



      threshold_value = each.value.threshold



      aggregations {

        alignment_period = "60s"

        per_series_aligner = "ALIGN_MEAN"

      }

    }

  }



  notification_channels = values(

    var.notification_channels

  )

}