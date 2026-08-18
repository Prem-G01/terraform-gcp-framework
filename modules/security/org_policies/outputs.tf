output "enforced_constraints" {
  description = "Constraint IDs actually enforced by this apply, for a quick sanity check against what var.* said should be on."
  value = compact([
    var.disable_service_account_key_creation ? "iam.disableServiceAccountKeyCreation" : "",
    var.restrict_vm_external_ips ? "compute.vmExternalIpAccess" : "",
    var.restrict_public_sql_ips ? "sql.restrictPublicIp" : "",
    var.require_os_login ? "compute.requireOsLogin" : "",
    var.skip_default_network_creation ? "compute.skipDefaultNetworkCreation" : "",
  ])
}
