# Regression coverage for two real bugs found 2026-08-24 (see
# docs/security.md and the module's own comments):
#
# 1. `cleanup_policy.enabled` was accessed unconditionally with zero
#    fallback — a repository config that omitted `cleanup_policy`
#    entirely would crash `terraform plan`.
# 2. `keep_count` was set explicitly in every real dev-config repository
#    (docker: 20, python/maven: 10) but silently ignored by the module —
#    only a DELETE-after-30-days policy was ever created, never the
#    KEEP/most_recent_versions policy GCP's schema actually needs to
#    implement "keep the last N versions."
#
# This module had no test coverage at all before this file.
#
# Run: cd modules/artifact_registry && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
}

run "omitted_cleanup_policy_creates_no_policies" {
  command = plan

  variables {
    config = {
      artifact_registry = {
        docker = {
          repository_id = "docker"
          format        = "DOCKER"
          location      = "asia-south1"
          description   = "Docker images repository"
        }
      }
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository.repository["docker"].cleanup_policies) == 0
    error_message = "omitting cleanup_policy entirely must create zero cleanup_policies blocks, not crash"
  }
}

run "enabled_with_keep_count_creates_both_delete_and_keep_policies" {
  command = plan

  variables {
    config = {
      artifact_registry = {
        docker = {
          repository_id = "docker"
          format        = "DOCKER"
          location      = "asia-south1"
          description   = "Docker images repository"
          cleanup_policy = {
            enabled    = true
            keep_count = 20
          }
        }
      }
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository.repository["docker"].cleanup_policies) == 2
    error_message = "enabled + keep_count must create exactly 2 policies: delete-old-versions and keep-recent-versions"
  }

  assert {
    condition     = contains([for p in google_artifact_registry_repository.repository["docker"].cleanup_policies : p.id], "keep-recent-versions")
    error_message = "keep_count must actually produce a KEEP/most_recent_versions cleanup policy, not be silently ignored"
  }

  assert {
    condition = anytrue([
      for p in google_artifact_registry_repository.repository["docker"].cleanup_policies :
      p.id == "keep-recent-versions" && try(p.most_recent_versions[0].keep_count, null) == 20
    ])
    error_message = "the KEEP policy's keep_count must match the configured value (20 for docker), not be hardcoded or dropped"
  }
}

run "enabled_without_keep_count_creates_only_the_delete_policy" {
  command = plan

  variables {
    config = {
      artifact_registry = {
        maven = {
          repository_id = "maven"
          format        = "MAVEN"
          location      = "asia-south1"
          description   = "Maven repository"
          cleanup_policy = {
            enabled = true
          }
        }
      }
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository.repository["maven"].cleanup_policies) == 1
    error_message = "enabled without keep_count must create only the delete-old-versions policy"
  }

  assert {
    condition     = contains([for p in google_artifact_registry_repository.repository["maven"].cleanup_policies : p.id], "delete-old-versions")
    error_message = "the single policy created without keep_count must be delete-old-versions"
  }
}
