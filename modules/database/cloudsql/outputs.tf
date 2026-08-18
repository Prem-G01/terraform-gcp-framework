output "names" {

  value = {

    for k, v in google_sql_database_instance.cloudsql :

    k => v.name

  }

}



output "private_ips" {

  value = {

    for k, v in google_sql_database_instance.cloudsql :

    k => v.private_ip_address

  }

}