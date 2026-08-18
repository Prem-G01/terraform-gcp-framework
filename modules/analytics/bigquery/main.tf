resource "google_bigquery_dataset" "dataset" {

  for_each = var.config.bigquery

  project = var.project_id

  dataset_id = lookup(each.value, "dataset_id", each.key)

  location = each.value.location

  description = lookup(
    each.value,
    "description",
    ""
  )

  delete_contents_on_destroy = lookup(
    each.value,
    "delete_contents_on_destroy",
    false
  )

  default_table_expiration_ms = lookup(
    each.value,
    "default_table_expiration_ms",
    null
  )

}



locals {

  tables = flatten([

    for dataset_name, dataset in var.config.bigquery : [

      for table_name, table in lookup(
        dataset,
        "tables",
        {}
        ) : {

        dataset_name = dataset_name

        table_name = table_name

        table = table

      }

    ]

  ])



  tables_map = {

    for t in local.tables :

    "${t.dataset_name}-${t.table_name}" => t

  }

}



resource "google_bigquery_table" "table" {

  for_each = local.tables_map

  project = var.project_id

  dataset_id = google_bigquery_dataset.dataset[
    each.value.dataset_name
  ].dataset_id

  table_id = each.value.table.table_id

  deletion_protection = lookup(each.value.table, "deletion_protection", true)

}