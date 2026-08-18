output "repositories" {

  value = {

    for k, v in google_artifact_registry_repository.repository :

    k => v.name

  }

}



output "repository_urls" {

  value = {

    for k, v in google_artifact_registry_repository.repository :

    k => v.id

  }

}