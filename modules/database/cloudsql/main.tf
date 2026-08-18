resource "google_sql_database_instance" "cloudsql" {

  for_each = var.config.cloudsql

  project = var.project_id

  name = lookup(each.value, "name", each.key)

  region = each.value.region

  database_version = each.value.database_version

  deletion_protection = each.value.deletion_protection



  settings {

    tier = each.value.tier

    availability_type = each.value.availability_type



    disk_size = each.value.disk.size

    disk_type = each.value.disk.type

    disk_autoresize = each.value.disk.autoresize



    backup_configuration {

      enabled = each.value.backup.enabled

      start_time = each.value.backup.start_time

    }



    ip_configuration {

      ipv4_enabled = each.value.network.ipv4_enabled

      private_network = var.vpcs[

        each.value.network.private_network

      ]

    }



    insights_config {

      query_insights_enabled = each.value.insights.query_insights_enabled

      query_string_length = each.value.insights.query_string_length

      record_application_tags = each.value.insights.record_application_tags

      record_client_address = each.value.insights.record_client_address

    }

  }

}


locals {

  sql_users = flatten([

    for instance_name, instance in var.config.cloudsql : [

      for user_name, user in lookup(instance, "users", {}) : {

        instance_name = instance_name

        username = user.username

        secret_name = user.password_secret

        host = lookup(user, "host", "%")

      }

    ]

  ])

  sql_users_map = {
    for u in local.sql_users :
    "${u.instance_name}-${u.username}" => u
  }

}

resource "google_sql_user" "users" {

  for_each = local.sql_users_map

  project  = var.project_id
  instance = google_sql_database_instance.cloudsql[each.value.instance_name].name

  name     = each.value.username
  host     = each.value.host
  password = var.passwords[each.value.secret_name]
}