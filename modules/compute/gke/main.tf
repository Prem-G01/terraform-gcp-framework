# Private-by-construction GKE: workload identity, network policy, and
# shielded nodes are always on — not config toggles, because there's no
# legitimate case in this platform for a cluster with them off (see
# docs/security.md). What IS configurable per deployment.yaml: node pool
# sizing, master CIDR, and whether the API endpoint is reachable
# externally at all (private_cluster.enable_private_endpoint).

resource "google_container_cluster" "cluster" {
  for_each = var.config.gke

  project  = var.project_id
  name     = lookup(each.value, "name", each.key)
  location = each.value.location

  network    = var.vpcs[each.value.network]
  subnetwork = var.subnets[each.value.subnet]

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  # Every node pool is managed as a separate google_container_node_pool
  # below — the cluster's own default pool is never used.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = lookup(each.value, "release_channel", "REGULAR")
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = lookup(each.value.private_cluster, "enable_private_nodes", true)
    enable_private_endpoint = lookup(each.value.private_cluster, "enable_private_endpoint", false)
    master_ipv4_cidr_block  = each.value.private_cluster.master_ipv4_cidr_block
  }

  network_policy {
    enabled  = lookup(each.value, "network_policy_enabled", true)
    provider = "CALICO"
  }

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  deletion_protection = lookup(each.value, "deletion_protection", true)
}

resource "google_container_node_pool" "pool" {
  for_each = var.config.gke

  project  = var.project_id
  name     = "${lookup(each.value, "name", each.key)}-pool"
  location = each.value.location
  cluster  = google_container_cluster.cluster[each.key].name

  node_count = lookup(each.value.node_pool, "autoscaling", null) == null ? lookup(each.value.node_pool, "node_count", 1) : null

  dynamic "autoscaling" {
    for_each = lookup(each.value.node_pool, "autoscaling", null) != null ? [each.value.node_pool.autoscaling] : []
    content {
      min_node_count = autoscaling.value.min_node_count
      max_node_count = autoscaling.value.max_node_count
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = each.value.node_pool.machine_type
    disk_size_gb = lookup(each.value.node_pool, "disk_size_gb", 50)
    disk_type    = lookup(each.value.node_pool, "disk_type", "pd-balanced")

    service_account = var.service_accounts[each.value.node_pool.service_account]
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
