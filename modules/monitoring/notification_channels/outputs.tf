output "channels" {

  value = {

    for k, v in google_monitoring_notification_channel.channels :

    k => v.name

  }

}