output "function_names" {
  value = { for k, v in google_cloudfunctions2_function.function : k => v.name }
}

output "urls" {
  value = { for k, v in google_cloudfunctions2_function.function : k => v.url }
}
