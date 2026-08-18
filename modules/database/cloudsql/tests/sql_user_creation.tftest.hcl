# Direct regression test for the real bug fixed in this rebuild: the
# original module computed local.sql_users from config but never created
# a google_sql_user resource, so every declared database user silently
# never existed even though the instance and its Secret Manager password
# were created. Tests this module in isolation (not through platform/) so
# it can assert on the actual resource, not just an output.
#
# Run: cd modules/database/cloudsql && terraform test

mock_provider "google" {}

variables {
  project_id = "prj-dg-devops-test"
  vpcs       = { "test-vpc" = "projects/prj-dg-devops-test/global/networks/test-vpc" }
  passwords  = { "root-password" = "mock-generated-password" }

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
        network             = { private_network = "test-vpc", ipv4_enabled = false }
        insights = {
          query_insights_enabled  = true
          query_string_length     = 1024
          record_application_tags = true
          record_client_address   = true
        }
        users = {
          root = { username = "root", password_secret = "root-password", host = "%" }
        }
      }
    }
  }
}

run "sql_user_is_created_for_every_configured_user" {
  command = plan

  assert {
    condition     = google_sql_user.users["test-sql-root"].name == "root"
    error_message = "google_sql_user for the 'root' user was not planned — the users-never-created bug may have regressed"
  }

  assert {
    condition     = google_sql_user.users["test-sql-root"].instance == "test-sql"
    error_message = "google_sql_user should attach to the test-sql instance by name"
  }

  assert {
    condition     = google_sql_user.users["test-sql-root"].host == "%"
    error_message = "host should default from the configured user, not be silently dropped"
  }

  assert {
    condition     = google_sql_database_instance.cloudsql["test-sql"].deletion_protection == true
    error_message = "deletion_protection should pass through from config"
  }
}

run "no_users_created_when_none_configured" {
  command = plan

  variables {
    config = {
      cloudsql = {
        bare-sql = {
          region              = "asia-south1"
          database_version    = "MYSQL_8_0"
          tier                = "db-f1-micro"
          availability_type   = "ZONAL"
          deletion_protection = true
          disk                = { size = 20, type = "PD_SSD", autoresize = true }
          backup              = { enabled = false, start_time = "00:00" }
          network             = { private_network = "test-vpc", ipv4_enabled = false }
          insights = {
            query_insights_enabled  = false
            query_string_length     = 1024
            record_application_tags = false
            record_client_address   = false
          }
        }
      }
    }
  }

  assert {
    condition     = length(google_sql_user.users) == 0
    error_message = "An instance with no users configured should create zero google_sql_user resources"
  }
}
