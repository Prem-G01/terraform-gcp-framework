output "processors" {

  value = {

    for k, v in google_document_ai_processor.processor :

    k => {

      id = v.id

      name = v.name

      location = v.location

    }

  }

}