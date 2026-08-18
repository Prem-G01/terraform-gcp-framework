resource "google_monitoring_uptime_check_config" "uptime" {

  for_each = var.config.uptime_checks



  project = var.project_id



  display_name = each.value.display_name



  timeout = "10s"



  period = "60s"



  http_check {



    path = each.value.path



    port = each.value.port



    use_ssl = each.value.use_ssl

  }



  monitored_resource {



    type = "uptime_url"



    labels = {



      host = each.value.host

    }

  }

}