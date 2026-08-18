# Native `terraform test` (Terraform >= 1.7) — runs entirely offline via
# mock_provider, no GCP credentials or network access needed. Proves the
# core promise of platform/main.tf: a disabled resource type contributes
# nothing to the plan, and an enabled one shows up correctly.
#
# Deliberately uses `buckets` (no cross-module self_link chaining) rather
# than something like `cloudsql` — feeding a mocked VPC self_link into a
# field the provider schema validates as a real resource URL fails under
# mock_provider even though it's correct with a real GCP backend. Resource-
# level correctness for a specific module (e.g. the Cloud SQL user-creation
# regression) is covered in that module's own tests/ directory instead —
# see modules/database/cloudsql/tests/sql_user_creation.tftest.hcl.
#
# Run: cd platform && terraform test

mock_provider "google" {}

variables {
  project_id  = "prj-dg-devops-test"
  environment = "dev"
}

run "all_disabled_produces_no_resources" {
  command = plan

  variables {
    deployment_file = "tests/fixtures/all_disabled.json"
  }

  assert {
    condition     = length(output.enabled_resources) == 0
    error_message = "An empty resources block should leave every type disabled — got: ${jsonencode(output.enabled_resources)}"
  }
}

run "buckets_enabled_creates_the_bucket_and_nothing_else" {
  command = plan

  variables {
    deployment_file = "tests/fixtures/buckets_enabled.json"
  }

  assert {
    condition     = output.enabled_resources.buckets == true
    error_message = "buckets should be enabled per the fixture"
  }

  assert {
    condition     = contains(keys(output.bucket_names), "test-bucket")
    error_message = "Expected the test-bucket instance to be planned"
  }

  # Every other type must stay absent — proves enabling one type doesn't
  # accidentally pull in others.
  assert {
    condition     = length(output.enabled_resources) == 1
    error_message = "Only 'buckets' should be enabled — got: ${jsonencode(output.enabled_resources)}"
  }
}
