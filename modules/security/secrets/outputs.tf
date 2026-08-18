output "passwords" {

  sensitive = true



  value = {

    for k, v in random_password.passwords :

    k => v.result

  }

}



output "secret_ids" {

  value = {

    for k, v in google_secret_manager_secret.secrets :

    k => v.secret_id

  }

}



output "secret_names" {

  value = {

    for k, v in google_secret_manager_secret.secrets :

    k => v.name

  }

}