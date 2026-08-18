output "emails" {

  value = {

    for k, v in google_service_account.service_accounts :

    k => v.email

  }

}



output "ids" {

  value = {

    for k, v in google_service_account.service_accounts :

    k => v.id

  }

}