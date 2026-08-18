output "datasets" {

  value = {

    for k, v in google_bigquery_dataset.dataset :

    k => v.dataset_id

  }

}



output "tables" {

  value = {

    for k, v in google_bigquery_table.table :

    k => v.table_id

  }

}