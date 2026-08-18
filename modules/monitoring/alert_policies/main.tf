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

        alignment_period = lookup(
          each.value,
          "alignment_period",
          "60s"
        )

        # ALIGN_MEAN only makes sense for a GAUGE metric (CPU/memory
        # utilization ratios). A cumulative counter (e.g. Cloud Functions
        # execution_count) needs ALIGN_RATE or ALIGN_DELTA; a BOOL
        # condition metric (e.g. GKE node status_condition) needs
        # ALIGN_FRACTION_TRUE or ALIGN_COUNT_TRUE. Get this wrong and the
        # policy either fails to create or silently never fires — see
        # docs/modules.md "Alert policy aligners" before adding a new one.
        per_series_aligner = lookup(
          each.value,
          "aligner",
          "ALIGN_MEAN"
        )

      }

    }

  }



  notification_channels = values(

    var.notification_channels

  )

}