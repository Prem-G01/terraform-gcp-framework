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

    dynamic "access_config" {
      for_each = each.value.network.public_ip ? [1] : []
      content {}
    }
  }

  service_account {
    email = var.service_accounts[
      each.value.service_account.name
    ]
    scopes = each.value.service_account.scopes
  }

  shielded_instance_config {
    enable_secure_boot          = each.value.shielded_vm.secure_boot
    enable_vtpm                 = each.value.shielded_vm.vtpm
    enable_integrity_monitoring = each.value.shielded_vm.integrity_monitoring
  }

}