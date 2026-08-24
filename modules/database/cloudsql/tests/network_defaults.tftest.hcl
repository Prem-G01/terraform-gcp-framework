# Regression test for the real gap a security_defaults audit found
# (2026-08-19, see docs/security.md): network.ipv4_enabled was a hard-
# required each.value.field reference with zero fallback — safe only
# because every real environment's config happened to set it explicitly.
#
# Run: cd modules/database/cloudsql && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
  vpcs       = { "test-vpc" = "projects/prj-dg-devops-test/global/networks/test-vpc" }
  passwords  = { "root-password" = "mock-generated-password" }
}

run "omitted_ipv4_enabled_falls_back_to_no_public_ip" {
  command = plan

  variables {
    config = {
      cloudsql = {
        test-sql = {
          region              = "asia-south1"
          database_version    = "MYSQL_8_0"
          tier                = "db-custom-2-4096"
          availability_type   = "ZONAL"
          deletion_protection = true
          disk                = { size = 50, type = "PD_SSD", autoresize = true }
          backup              = { enabled = true, start_time = "00:00" }
          # network.ipv4_enabled is deliberately omitted here —
          # network.private_network is still required, no sensible
          # default exists for which VPC to use.
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
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "network.ipv4_enabled must default to false (no public IP) when omitted from config"
  }
}

run "explicit_ipv4_enabled_is_never_overridden" {
  command = plan

  variables {
    config = {
      cloudsql = {
        test-sql = {
          region              = "asia-south1"
          database_version    = "MYSQL_8_0"
          tier                = "db-custom-2-4096"
          availability_type   = "ZONAL"
          deletion_protection = true
          disk                = { size = 50, type = "PD_SSD", autoresize = true }
          backup              = { enabled = true, start_time = "00:00" }
          network             = { private_network = "test-vpc", ipv4_enabled = true }
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
    condition     = google_sql_database_instance.cloudsql["test-sql"].settings[0].ip_configuration[0].ipv4_enabled == true
    error_message = "an explicit network.ipv4_enabled = true must never be silently overridden to false"
  }
}
