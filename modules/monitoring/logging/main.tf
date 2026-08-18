resource "google_logging_project_bucket_config" "bucket" {

  for_each = var.config.logging



  project = var.project_id



  bucket_id = each.value.bucket_id



  location = lookup(

    each.value,

    "location",

    "global"

  )



  retention_days = lookup(

    each.value,

    "retention_days",

    30

  )

}