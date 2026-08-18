output "instance_names" {
  value = { for k, v in google_redis_instance.cache : k => v.name }
}

output "hosts" {
  value = { for k, v in google_redis_instance.cache : k => v.host }
}

output "auth_strings" {
  value     = { for k, v in google_redis_instance.cache : k => v.auth_string }
  sensitive = true
}
