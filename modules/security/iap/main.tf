# Identity-Aware Proxy tunnel access — the zero-trust replacement for a
# bastion host or a firewall rule that trusts "came from the office IP
# range." Every access is authenticated per-request against IAM, not
# against network location; the `allow-iap` firewall rule (source_ranges
# = 35.235.240.0/20, Google's fixed IAP relay range — see
# config/environments/dev/deployment.yaml `firewall.instances.allow-iap`)
# only lets traffic reach the instance at all, this module is what
# actually authorizes who's allowed to open a tunnel through it.
#
# Expected `var.config` shape (resources.iap.instances in deployment.yaml):
#   <name>:
#     target_vm: "app-vm-01"                    # key into resources.vm.instances
#     members: ["group:platform-admins@example.com"]
#     role: "roles/iap.tunnelResourceAccessor"  # optional, this is already the default

locals {
  # Flatten (instance-config x member) into one entry per IAM binding —
  # google_iap_tunnel_instance_iam_member is additive (unlike the
  # authoritative _iam_binding variant), matching every other IAM
  # resource in this platform (see modules/storage/buckets,
  # modules/iam/service_accounts).
  bindings = merge([
    for name, cfg in var.config : {
      for member in cfg.members :
      "${name}-${member}" => {
        target_vm = cfg.target_vm
        member    = member
        role      = lookup(cfg, "role", "roles/iap.tunnelResourceAccessor")
      }
    }
  ]...)
}

resource "google_iap_tunnel_instance_iam_member" "access" {
  for_each = local.bindings

  project  = var.project_id
  zone     = var.vm_zones[each.value.target_vm]
  instance = var.vm_names[each.value.target_vm]
  role     = each.value.role
  member   = each.value.member
}
