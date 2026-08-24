# Regression coverage for real name generation, added 2026-08-24 (see
# main.tf's header comment). This module had zero test coverage before —
# it was instantiated in platform/main.tf but its outputs were never
# referenced anywhere, and it never actually implemented
# config/global/naming.yaml's pattern templates despite claiming to.
#
# This is a zero-resource module (locals + outputs only, no provider
# calls) — no mock_provider needed.
#
# Run: cd modules/shared/naming && terraform test

variables {
  organization = { company = "DG" }
  naming = {
    separator = "-"
    pattern = {
      default = "{company}-{environment}-{service}-{name}"
      project = "{company}-{environment}-{name}"
      vm      = "{company}-{environment}-vm-{name}"
      sql     = "{company}-{environment}-sql-{name}"
    }
  }
  environment = "dev"
}

run "generates_the_documented_pattern_for_vm_and_sql" {
  command = plan

  variables {
    instance_keys = {
      vm  = ["app-vm-01"]
      sql = ["app-sql"]
    }
  }

  assert {
    condition     = output.generated_names.vm["app-vm-01"] == "dg-dev-vm-app-vm-01"
    error_message = "vm pattern must interpolate to company-environment-vm-name, got: ${output.generated_names.vm["app-vm-01"]}"
  }

  assert {
    condition     = output.generated_names.sql["app-sql"] == "dg-dev-sql-app-sql"
    error_message = "sql pattern must interpolate to company-environment-sql-name, got: ${output.generated_names.sql["app-sql"]}"
  }
}

run "uppercase_company_is_always_lowercased" {
  command = plan

  # The real bug this locks in: organization.company is "DG" (uppercase)
  # in the real config/global/defaults.yaml, and google_compute_instance
  # .name must match ^[a-z]([-a-z0-9]*[a-z0-9])?$ — a real plan against
  # live GCP failed outright on "DG-dev-vm-app-vm-01" before this was
  # fixed. Every generated name must be lowercase regardless of the
  # company value's own casing.
  variables {
    instance_keys = {
      vm = ["app-vm-01"]
    }
  }

  assert {
    condition     = output.generated_names.vm["app-vm-01"] == lower(output.generated_names.vm["app-vm-01"])
    error_message = "generated names must always be lowercase, got: ${output.generated_names.vm["app-vm-01"]}"
  }
}

run "no_instance_keys_produces_no_generated_names" {
  command = plan

  variables {
    instance_keys = {}
  }

  assert {
    condition     = output.generated_names == {}
    error_message = "empty instance_keys must produce an empty generated_names map, not error"
  }
}

run "separator_and_company_pass_through_are_unchanged" {
  command = plan

  variables {
    instance_keys = {}
  }

  assert {
    condition     = output.separator == "-"
    error_message = "separator output must still pass through naming.yaml's separator unchanged"
  }

  assert {
    condition     = output.company == "DG"
    error_message = "company output must still pass through organization.company unchanged (case preserved — only generated_names is lowercased)"
  }
}
