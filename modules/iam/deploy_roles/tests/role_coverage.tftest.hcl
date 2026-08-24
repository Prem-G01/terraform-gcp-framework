# Regression coverage for a real, significant gap found 2026-08-24: this
# module is the single source of truth for every role the real
# tf-apply-<env>/tf-plan-<env> identities get, in both bootstrap/main.tf
# (home environment) and bootstrap/grants/main.tf (every spoke project) —
# but it had zero test coverage, and an audit against the installed IAM
# role definitions found 10 real gaps: GKE, Cloud Tasks queue management,
# Memorystore, Private Service Access, VPC Service Controls, Binary
# Authorization, Cloud Functions gen2, Document AI, IAP tunnel IAM
# bindings, and Org Policies all either had no matching role at all or
# the wrong one. None of this was ever caught because every real apply
# this platform has done used a human operator's own ADC credentials
# directly, never the real tf-apply-<env> identity via WIF — see
# docs/service-accounts.md.
#
# This is a zero-resource module (locals + outputs only, no provider
# calls) — no mock_provider or variables needed.
#
# Run: cd modules/iam/deploy_roles && terraform test

run "apply_sa_roles_covers_every_resource_type_this_platform_creates" {
  command = plan

  # Spot-checks the roles found missing in the 2026-08-24 audit — one per
  # resource type family, verified against `gcloud iam roles describe`
  # to actually include the create/update/delete permission each
  # corresponding module needs, not just assumed from the role's name.
  assert {
    condition     = contains(output.apply_sa_roles, "roles/container.admin")
    error_message = "roles/container.admin is required for modules/compute/gke — roles/compute.admin has zero container.* permissions"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/cloudtasks.admin")
    error_message = "roles/cloudtasks.admin is required for modules/messaging/cloudtasks to create/update/delete queues"
  }

  assert {
    condition     = !contains(output.apply_sa_roles, "roles/cloudtasks.enqueuer")
    error_message = "roles/cloudtasks.enqueuer only grants runtime task enqueuing, not queue management — must never reappear as a substitute for roles/cloudtasks.admin"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/redis.admin")
    error_message = "roles/redis.admin is required for modules/database/memorystore"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/servicenetworking.networksAdmin")
    error_message = "roles/servicenetworking.networksAdmin is required for modules/networking/private_service_access"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/accesscontextmanager.policyAdmin")
    error_message = "roles/accesscontextmanager.policyAdmin is required for modules/security/vpc_service_controls"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/binaryauthorization.policyAdmin")
    error_message = "roles/binaryauthorization.policyAdmin is required for modules/security/binary_authorization"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/cloudfunctions.admin")
    error_message = "roles/cloudfunctions.admin is required for modules/compute/cloudfunctions"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/documentai.admin")
    error_message = "roles/documentai.admin is required for modules/ai/documentai"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/iap.admin")
    error_message = "roles/iap.admin is required for modules/security/iap's google_iap_tunnel_instance_iam_member"
  }

  assert {
    condition     = contains(output.apply_sa_roles, "roles/orgpolicy.policyAdmin")
    error_message = "roles/orgpolicy.policyAdmin is required for modules/security/org_policies — this is the SAME gap that has independently blocked a human operator's own org_policies apply all session"
  }
}

run "apply_sa_roles_never_grants_broad_roles" {
  command = plan

  # SEC_OVERPRIVILEGED_SERVICE_ACCOUNT (config/global/security.yaml) is
  # the policy this list exists to satisfy — this asserts the
  # implementation actually matches that intent, not just the comment
  # claiming it does.
  assert {
    condition     = !contains(output.apply_sa_roles, "roles/editor")
    error_message = "apply_sa_roles must never include roles/editor"
  }

  assert {
    condition     = !contains(output.apply_sa_roles, "roles/owner")
    error_message = "apply_sa_roles must never include roles/owner"
  }
}
