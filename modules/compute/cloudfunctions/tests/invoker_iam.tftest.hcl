# Regression test for a real bug found 2026-08-25: this module had no
# invoker mechanism at all. ALLOW_INTERNAL_ONLY (the secure default) still
# returned 403 to a legitimate in-VPC caller, because nothing granted
# invoker access to anyone. Confirmed against real GCP that
# google_cloudfunctions2_function_iam_member does NOT gate actual HTTP
# invocation — that's controlled by the underlying Cloud Run service's own
# IAM policy (google_cloud_run_v2_service_iam_member), a separate ACL. This
# module had no test coverage for the invoker binding before this (see
# scaling_and_resources_defaults.tftest.hcl for the module's other gap).
#
# Run: cd modules/compute/cloudfunctions && terraform test

mock_provider "google" {}

variables {
  project_id       = "prj-dg-devops-test"
  service_accounts = { "function-sa" = "function-sa@prj-dg-devops-test.iam.gserviceaccount.com" }
}

run "omitted_invoker_members_grants_no_invoker_binding" {
  command = plan

  variables {
    config = {
      cloudfunctions = {
        process-upload = {
          location    = "asia-south1"
          runtime     = "python312"
          entry_point = "process_upload"
          source = {
            bucket = "prj-dg-devops-test-dev-app-storage"
            object = "functions/process-upload.zip"
          }
          service_account = { name = "function-sa" }
          # invoker_members is deliberately omitted here.
        }
      }
    }
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "Omitting invoker_members must grant zero invoker bindings — deny-by-default, matching ALLOW_INTERNAL_ONLY's intent"
  }
}

run "invoker_members_grants_bindings_on_the_underlying_cloud_run_service" {
  command = plan

  variables {
    config = {
      cloudfunctions = {
        process-upload = {
          location    = "asia-south1"
          runtime     = "python312"
          entry_point = "process_upload"
          source = {
            bucket = "prj-dg-devops-test-dev-app-storage"
            object = "functions/process-upload.zip"
          }
          service_account = { name = "function-sa" }
          invoker_members = ["serviceAccount:vm-service-account@prj-dg-devops-test.iam.gserviceaccount.com"]
        }
      }
    }
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invoker["process-upload-serviceAccount:vm-service-account@prj-dg-devops-test.iam.gserviceaccount.com"].role == "roles/run.invoker"
    error_message = "invoker_members must grant roles/run.invoker on the underlying Cloud Run service, not roles/cloudfunctions.invoker — confirmed against real GCP that the latter never reaches the Cloud Run IAM policy that actually gates HTTP invocation"
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invoker["process-upload-serviceAccount:vm-service-account@prj-dg-devops-test.iam.gserviceaccount.com"].member == "serviceAccount:vm-service-account@prj-dg-devops-test.iam.gserviceaccount.com"
    error_message = "the binding must grant exactly the configured member, not allUsers — ALLOW_INTERNAL_ONLY functions should never be openly invokable"
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invoker["process-upload-serviceAccount:vm-service-account@prj-dg-devops-test.iam.gserviceaccount.com"].name == google_cloudfunctions2_function.function["process-upload"].name
    error_message = "the binding must target the function's underlying Cloud Run service by name (they share the same name), not a separate Cloud Functions-specific IAM resource"
  }
}
