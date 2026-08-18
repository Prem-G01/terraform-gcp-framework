resource "google_document_ai_processor" "processor" {

  for_each = var.config.documentai



  project = var.project_id



  location = each.value.location



  display_name = each.value.display_name



  type = each.value.type

}