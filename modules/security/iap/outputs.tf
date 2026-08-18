output "bindings" {
  description = "Map of every IAP tunnel IAM binding this apply created — target_vm, member, role — for a quick access-review printout without going to the console."
  value = {
    for k, v in google_iap_tunnel_instance_iam_member.access :
    k => { target_vm = v.instance, member = v.member, role = v.role }
  }
}
