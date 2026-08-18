output "buckets" {

  value = {

    for k, v in google_logging_project_bucket_config.bucket :

    k => v.bucket_id

  }

}



output "bucket_ids" {

  value = {

    for k, v in google_logging_project_bucket_config.bucket :

    k => v.id

  }

}