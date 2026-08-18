output "uptime_checks" {

  value = {

    for k, v in google_monitoring_uptime_check_config.uptime :

    k => v.name

  }

}