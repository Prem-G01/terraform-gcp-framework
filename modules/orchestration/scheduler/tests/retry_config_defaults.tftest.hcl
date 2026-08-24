# Regression test for a real gap found 2026-08-24: `retry_config` was a
# hard-required each.value reference with no fallback for the whole
# block, even though every field inside it already had a lookup()
# default — a job config that omitted retry_config entirely would crash
# terraform plan. This module had no test coverage at all before this.
#
# Run: cd modules/orchestration/scheduler && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_retry_config_falls_back_to_documented_defaults" {
  command = plan

  variables {
    config = {
      scheduler = {
        cleanup-job = {
          location = "asia-south1"
          schedule = "0 1 * * *"
          http_target = {
            uri = "https://example.com/cleanup"
          }
          # retry_config is deliberately omitted here.
        }
      }
    }
  }

  assert {
    condition     = google_cloud_scheduler_job.job["cleanup-job"].retry_config[0].retry_count == 3
    error_message = "retry_config.retry_count should default to 3 when the whole retry_config block is omitted"
  }

  assert {
    condition     = google_cloud_scheduler_job.job["cleanup-job"].retry_config[0].max_retry_duration == "300s"
    error_message = "retry_config.max_retry_duration should default to 300s when the whole retry_config block is omitted"
  }
}

run "explicit_retry_config_is_never_overridden" {
  command = plan

  variables {
    config = {
      scheduler = {
        cleanup-job = {
          location = "asia-south1"
          schedule = "0 1 * * *"
          http_target = {
            uri = "https://example.com/cleanup"
          }
          retry_config = {
            retry_count        = 7
            max_retry_duration = "600s"
          }
        }
      }
    }
  }

  assert {
    condition     = google_cloud_scheduler_job.job["cleanup-job"].retry_config[0].retry_count == 7
    error_message = "an explicit retry_config.retry_count must never be silently overridden to the default of 3"
  }

  assert {
    condition     = google_cloud_scheduler_job.job["cleanup-job"].retry_config[0].max_retry_duration == "600s"
    error_message = "an explicit retry_config.max_retry_duration must never be silently overridden to the default of 300s"
  }
}
