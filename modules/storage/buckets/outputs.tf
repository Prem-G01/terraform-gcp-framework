output "bucket_names" {

  value = {

    for k, v in google_storage_bucket.bucket :

    k => v.name

  }

}



output "bucket_urls" {

  value = {

    for k, v in google_storage_bucket.bucket :

    k => v.url

  }

}



output "bucket_self_links" {

  value = {

    for k, v in google_storage_bucket.bucket :

    k => v.self_link

  }

}