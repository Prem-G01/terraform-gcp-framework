output "bindings" {
  value = {
    for k, v in google_service_account_iam_member.workload_identity_binding :
    k => { service_account_id = v.service_account_id, member = v.member }
  }
}
