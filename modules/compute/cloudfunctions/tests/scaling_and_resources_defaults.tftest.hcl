# Regression test for a real gap found 2026-08-24: `scaling` and
# `resources` were each hard-required each.value references with no
# fallback for the whole object, even though every field inside already
# had a lookup() default — same gap class found in cloudsql,
# artifact_registry, scheduler, and cloudtasks earlier the same day. An
# instance config that omitted either block entirely would crash
# terraform plan. This module had no test coverage at all before this.
#
# Run: cd modules/compute/cloudfunctions && terraform test

mock_provider "google" {}

variables {
  project_id       = "prj-dg-devops-test"
  service_accounts = { "function-sa" = "function-sa@prj-dg-devops-test.iam.gserviceaccount.com" }
}

run "omitted_scaling_and_resources_fall_back_to_documented_defaults" {
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
          # scaling and resources are deliberately omitted here.
        }
      }
    }
  }

  assert {
    condition     = google_cloudfunctions2_function.function["process-upload"].service_config[0].max_instance_count == 3
    error_message = "scaling.max_instance_count should default to 3 when the whole scaling block is omitted"
  }

  assert {
    condition     = google_cloudfunctions2_function.function["process-upload"].service_config[0].available_memory == "256M"
    error_message = "resources.memory should default to 256M when the whole resources block is omitted"
  }
}

run "explicit_scaling_and_resources_are_never_overridden" {
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
          scaling         = { max_instance_count = 10 }
          resources       = { memory = "512M" }
        }
      }
    }
  }

  assert {
    condition     = google_cloudfunctions2_function.function["process-upload"].service_config[0].max_instance_count == 10
    error_message = "an explicit scaling.max_instance_count must never be silently overridden to the default of 3"
  }

  assert {
    condition     = google_cloudfunctions2_function.function["process-upload"].service_config[0].available_memory == "512M"
    error_message = "an explicit resources.memory must never be silently overridden to the default of 256M"
  }
}
