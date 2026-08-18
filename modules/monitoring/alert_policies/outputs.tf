output "alert_policies" {

  value = {

    for k, v in google_monitoring_alert_policy.alerts :

    k => v.name

  }

}