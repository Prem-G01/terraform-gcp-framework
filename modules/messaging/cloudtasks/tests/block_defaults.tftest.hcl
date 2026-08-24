# Regression test for a real gap found 2026-08-24: rate_limits,
# retry_config, and stackdriver_logging_config were each a hard-required
# each.value reference with no fallback for the whole block, even though
# every field inside already had a lookup() default — a queue config
# that omitted any of the three entirely would crash terraform plan.
# This module had no test coverage at all before this.
#
# Run: cd modules/messaging/cloudtasks && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_blocks_fall_back_to_documented_defaults" {
  command = plan

  variables {
    config = {
      cloudtasks = {
        app-queue = {
          location = "asia-south1"
          # rate_limits, retry_config, and stackdriver_logging_config
          # are all deliberately omitted here.
        }
      }
    }
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].rate_limits[0].max_dispatches_per_second == 10
    error_message = "rate_limits.max_dispatches_per_second should default to 10 when the whole rate_limits block is omitted"
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].retry_config[0].max_attempts == 5
    error_message = "retry_config.max_attempts should default to 5 when the whole retry_config block is omitted"
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].stackdriver_logging_config[0].sampling_ratio == 1.0
    error_message = "stackdriver_logging_config.sampling_ratio should default to 1.0 when the whole block is omitted"
  }
}

run "explicit_values_are_never_overridden" {
  command = plan

  variables {
    config = {
      cloudtasks = {
        app-queue = {
          location = "asia-south1"
          rate_limits = {
            max_dispatches_per_second = 50
          }
          retry_config = {
            max_attempts = 10
          }
          stackdriver_logging_config = {
            sampling_ratio = 0.5
          }
        }
      }
    }
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].rate_limits[0].max_dispatches_per_second == 50
    error_message = "an explicit rate_limits.max_dispatches_per_second must never be silently overridden to the default of 10"
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].retry_config[0].max_attempts == 10
    error_message = "an explicit retry_config.max_attempts must never be silently overridden to the default of 5"
  }

  assert {
    condition     = google_cloud_tasks_queue.queue["app-queue"].stackdriver_logging_config[0].sampling_ratio == 0.5
    error_message = "an explicit stackdriver_logging_config.sampling_ratio must never be silently overridden to the default of 1.0"
  }
}
