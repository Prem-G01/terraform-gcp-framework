resource "google_compute_instance" "vm" {
  for_each     = var.config.vms
  project      = var.project_id
  name         = lookup(each.value, "name", each.key)
  zone         = each.value.zone
  machine_type = each.value.machine_type
  tags         = each.value.tags
  labels       = each.value.labels
  metadata     = each.value.metadata

  boot_disk {
    initialize_params {
      image = each.value.boot_disk.image
      size  = each.value.boot_disk.size_gb
      type  = each.value.boot_disk.type
    }
  }

  network_interface {
    subnetwork = var.subnets[
      each.value.subnet
    ]

    # Secure-by-default fallback matching config/global/defaults.yaml
    # security_defaults.compute.public_ip (false) — this platform's own
    # copy of that value, not a live reference (no module reads
    # security_defaults.yaml directly; see docs/security.md). Found
    # missing entirely while auditing for the same class of gap as the
    # deletion_protection fix in modules/compute/cloudrun.
    dynamic "access_config" {
      for_each = try(each.value.network.public_ip, false) ? [1] : []
      content {}
    }
  }

  service_account {
    email = var.service_accounts[
      each.value.service_account.name
    ]
    scopes = each.value.service_account.scopes
  }

  # Secure-by-default fallbacks matching
  # security_defaults.compute.shielded_vm (all true) — same reasoning as
  # network.public_ip above.
  shielded_instance_config {
    enable_secure_boot          = try(each.value.shielded_vm.secure_boot, true)
    enable_vtpm                 = try(each.value.shielded_vm.vtpm, true)
    enable_integrity_monitoring = try(each.value.shielded_vm.integrity_monitoring, true)
  }

  # Defaults to GCP's own native default (false), not this platform's
  # usual true-by-default for managed data stores (cloudsql/gke/bigquery/
  # workflows/cloudrun) — a machine_type or boot_disk.image change forces
  # google_compute_instance to be replaced, and deletion_protection=true
  # would block that routine, non-destructive lifecycle operation far
  # more often than it would for a rarely-replaced database or cluster.
  # Opt in per-instance for a VM that genuinely shouldn't be casually
  # replaced.
  deletion_protection = lookup(each.value, "deletion_protection", false)

}