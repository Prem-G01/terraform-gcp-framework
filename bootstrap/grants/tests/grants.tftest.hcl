# Regression coverage for bootstrap/grants/ — the stack that actually
# wires cross-project IAM for sit/uat/prod, and had zero test coverage
# despite being the single most consequential piece of multi-environment
# readiness. No real spoke project has ever had this applied against it
# (see docs/troubleshooting.md "Multi-environment readiness"), so this is
# the only verification this stack has had at all until that changes.
#
# Run: cd bootstrap/grants && terraform test

mock_provider "google" {}

variables {
  spoke_project_id   = "prj-dg-devops-test-sit"
  central_project_id = "prj-dg-devops-test"
  environment        = "sit"
  region             = "asia-south1"
}

run "sa_emails_resolve_to_the_central_project_not_the_spoke_project" {
  command = plan

  # A real, easy-to-get-wrong mistake: these identities live in
  # central_project_id (created once by bootstrap/main.tf) — this stack
  # only grants them roles *in* spoke_project_id, it must never construct
  # an email using the spoke project by mistake.
  assert {
    condition     = output.plan_sa_email == "tf-plan-sit@prj-dg-devops-test.iam.gserviceaccount.com"
    error_message = "plan_sa_email must be tf-plan-<env>@<central_project_id>, got: ${output.plan_sa_email}"
  }

  assert {
    condition     = output.apply_sa_email == "tf-apply-sit@prj-dg-devops-test.iam.gserviceaccount.com"
    error_message = "apply_sa_email must be tf-apply-<env>@<central_project_id>, got: ${output.apply_sa_email}"
  }
}

run "role_bindings_are_created_in_the_spoke_project_for_every_deploy_roles_entry" {
  command = plan

  # Every google_project_iam_member here must target spoke_project_id
  # (where this environment's real resources live), not central_project_id
  # — granting roles in the wrong project would silently leave the real
  # tf-apply-sit identity unable to do anything in sit itself.
  assert {
    condition = alltrue([
      for r in google_project_iam_member.apply_roles : r.project == "prj-dg-devops-test-sit"
    ])
    error_message = "every apply_roles binding must target spoke_project_id, not central_project_id"
  }

  assert {
    condition = alltrue([
      for r in google_project_iam_member.plan_roles : r.project == "prj-dg-devops-test-sit"
    ])
    error_message = "every plan_roles binding must target spoke_project_id, not central_project_id"
  }

  assert {
    condition     = length(google_project_iam_member.apply_roles) == length(module.deploy_roles.apply_sa_roles)
    error_message = "must create exactly one binding per role in deploy_roles.apply_sa_roles — a drift here means this stack and bootstrap/main.tf's home-environment grants disagree"
  }

  assert {
    condition     = length(google_project_iam_member.plan_roles) == length(module.deploy_roles.plan_sa_roles)
    error_message = "must create exactly one binding per role in deploy_roles.plan_sa_roles"
  }
}

run "log_sink_disabled_creates_nothing" {
  command = plan

  variables {
    create_log_sink = false
  }

  assert {
    condition     = length(google_logging_project_sink.central_log_export) == 0
    error_message = "create_log_sink = false must create zero logging sinks"
  }

  assert {
    condition     = length(google_project_service.logging) == 0
    error_message = "create_log_sink = false must not even enable the logging API — nothing here should depend on it"
  }

  assert {
    condition     = output.log_sink_writer_identity == null
    error_message = "log_sink_writer_identity must be null when create_log_sink is false"
  }
}

run "log_sink_enabled_targets_the_central_bucket" {
  command = plan

  variables {
    create_log_sink    = true
    central_log_bucket = "prj-dg-devops-test-logs-v3"
  }

  assert {
    condition     = google_logging_project_sink.central_log_export[0].destination == "storage.googleapis.com/prj-dg-devops-test-logs-v3"
    error_message = "the log sink must export to the real central_log_bucket, not a hardcoded or wrong bucket"
  }

  assert {
    condition     = google_logging_project_sink.central_log_export[0].project == "prj-dg-devops-test-sit"
    error_message = "the log sink itself must live in the spoke project, exporting FROM there TO the central bucket"
  }
}
