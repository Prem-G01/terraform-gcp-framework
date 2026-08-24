# Regression test for a real gap found 2026-08-24: `deletion_protection`
# and `backup` were both hard-required each.value references with zero
# fallback — the same shape as network_defaults.tftest.hcl's
# network.ipv4_enabled gap, but worse for deletion_protection
# specifically, because docs/security.md already documented it as fixed
# via lookup() when the module code never actually had that lookup.
# engine/security_engine.py's SEC_SQL_NO_DELETION_PROTECTION check only
# flags an *explicit* `false` (`sql.get("deletion_protection", True)`),
# so an omitted field passed validation cleanly while still crashing
# `terraform plan` — this test locks in that omitting it now resolves the
# same way validation already assumed it does.
#
# Run: cd modules/database/cloudsql && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
  vpcs       = { "test-vpc" = "projects/prj-dg-devops-test/global/networks/test-vpc" }
  passwords  = { "root-password" = "mock-generated-password" }
}

run "omitted_deletion_protection_and_backup_fall_back_to_safe_defaults" {
  command = plan

  variables {
    config = {
      cloudsql = {
        test-sql = {
          region            = "asia-south1"
          database_version  = "MYSQL_8_0"
          tier              = "db-custom-2-4096"
          availability_type = "ZONAL"
          disk              = { size = 50, type = "PD_SSD", autoresize = true }
          # deletion_protection and backup are deliberately omitted here.
          network = { private_network = "test-vpc" }
          insights = {
            query_insights_enabled  = true
            query_string_length     = 1024
            record_application_tags = true
            record_client_address   = true
          }
        }
      }
    }
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].deletion_protection == true
    error_message = "deletion_protection must default to true when omitted, matching engine/security_engine.py's SEC_SQL_NO_DELETION_PROTECTION assumption"
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].backup_configuration[0].enabled == true
    error_message = "backup.enabled must default to true when the whole backup block is omitted"
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].backup_configuration[0].start_time == "00:00"
    error_message = "backup.start_time must default to 00:00 when the whole backup block is omitted"
  }
}

run "explicit_deletion_protection_and_backup_are_never_overridden" {
  command = plan

  variables {
    config = {
      cloudsql = {
        test-sql = {
          region              = "asia-south1"
          database_version    = "MYSQL_8_0"
          tier                = "db-custom-2-4096"
          availability_type   = "ZONAL"
          deletion_protection = false
          disk                = { size = 50, type = "PD_SSD", autoresize = true }
          backup              = { enabled = false, start_time = "03:00" }
          network             = { private_network = "test-vpc" }
          insights = {
            query_insights_enabled  = true
            query_string_length     = 1024
            record_application_tags = true
            record_client_address   = true
          }
        }
      }
    }
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].deletion_protection == false
    error_message = "an explicit deletion_protection = false must never be silently overridden to true"
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].backup_configuration[0].enabled == false
    error_message = "an explicit backup.enabled = false must never be silently overridden to true"
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].backup_configuration[0].start_time == "03:00"
    error_message = "an explicit backup.start_time must never be silently overridden to the 00:00 default"
  }
}
