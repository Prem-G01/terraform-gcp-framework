output "service_names" {

  value = {

    for k, v in google_cloud_run_v2_service.cloudrun :

    k => v.name

  }

}



output "urls" {

  value = {

    for k, v in google_cloud_run_v2_service.cloudrun :

    k => v.uri

  }

}