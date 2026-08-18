# Tests this module in isolation (not through platform/) with a hand-
# supplied, correctly-shaped service_account_id — chaining through a
# mocked modules/iam/service_accounts instead fails under mock_provider:
# google_service_account.id is a computed attribute, and mock_provider's
# randomly-generated placeholder for it doesn't match the real
# self_link-shaped regex google_service_account_iam_member.service_account_id
# validates against. Same class of issue as the cloudsql self_link case
# documented in platform/tests/count_gating.tftest.hcl's header comment.
#
# Run: cd modules/security/workload_identity && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
  service_account_ids = {
    "app-workload-sa" = "projects/prj-dg-devops-test/serviceAccounts/app-workload-service-account@prj-dg-devops-test.iam.gserviceaccount.com"
  }

  config = {
    app-workload = {
      gcp_service_account = "app-workload-sa"
      k8s_namespace       = "default"
      k8s_service_account = "app-ksa"
    }
  }
}

run "binds_the_ksa_to_the_real_gcp_sa" {
  command = plan

  assert {
    condition     = google_service_account_iam_member.workload_identity_binding["app-workload"].role == "roles/iam.workloadIdentityUser"
    error_message = "Binding must grant roles/iam.workloadIdentityUser — that's the only role Workload Identity actually checks"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity_binding["app-workload"].member == "serviceAccount:prj-dg-devops-test.svc.id.goog[default/app-ksa]"
    error_message = "member must be the project.svc.id.goog[namespace/ksa] principal form GKE Workload Identity expects"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity_binding["app-workload"].service_account_id == var.service_account_ids["app-workload-sa"]
    error_message = "Binding should attach to the real GCP service account resolved from config[*].gcp_service_account, not a literal string"
  }
}

run "no_bindings_when_no_workload_identity_instances_configured" {
  command = plan

  variables {
    config = {}
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_binding) == 0
    error_message = "An empty config should create zero bindings"
  }
}
