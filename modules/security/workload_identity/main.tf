# Binds a Kubernetes ServiceAccount to a narrowly-scoped GCP service
# account via Workload Identity, so a pod authenticates as exactly the
# identity it needs — never the GKE node pool's own service account (see
# modules/compute/gke/main.tf, which already always sets
# workload_identity_config + workload_metadata_config = GKE_METADATA on
# every cluster/node pool; that's necessary but not sufficient — without a
# binding here, GKE_METADATA mode blocks metadata-server access entirely
# rather than falling back to the node SA, so a workload gets no GCP
# identity at all until it's explicitly onboarded here).
#
# Expected `var.config` shape (resources.workload_identity.instances):
#   <name>:
#     gcp_service_account: "app-workload-sa"   # key into resources.service_accounts.instances
#     k8s_namespace: "default"
#     k8s_service_account: "app-ksa"

resource "google_service_account_iam_member" "workload_identity_binding" {
  for_each = var.config

  service_account_id = var.service_account_ids[each.value.gcp_service_account]
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.k8s_namespace}/${each.value.k8s_service_account}]"
}
