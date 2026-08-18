resource "google_monitoring_notification_channel" "channels" {

  for_each = var.config.notification_channels

  project = var.project_id

  display_name = each.key

  type = each.value.type

  labels = {

    email_address = each.value.address

  }

}