resource "google_service_account" "service_accounts" {
  for_each     = var.config.service_accounts
  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
  description  = each.value.description

}


locals {

  iam_roles = flatten([

    for sa_name, sa in var.config.service_accounts : [

      for role in sa.roles : {

        sa_name = sa_name

        role = role

      }

    ]

  ])

}



resource "google_project_iam_member" "service_account_roles" {
  for_each = {
    for item in local.iam_roles :
    "${item.sa_name}-${replace(item.role, "/", "-")}" => item
  }
  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.service_accounts[each.value.sa_name].email}"

}