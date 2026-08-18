output "enabled_apis" {

  value = [

    for api in google_project_service.apis :

    api.service

  ]

}