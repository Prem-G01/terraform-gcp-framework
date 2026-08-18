# Project-wide default admission rule: only images meeting this policy
# can deploy to GKE (and any other Binary-Authorization-aware runtime in
# this project), regardless of who's deploying — even tf-apply-<env> with
# full compute.admin can't push an unattested image once this is
# ENFORCED_BLOCK_AND_AUDIT_LOG with REQUIRE_ATTESTATION. That's the point:
# identity-based trust (which this platform already does well — see
# docs/service-accounts.md) stops an over-privileged *deployer*; this
# stops an *unverified image*, a different attacker model entirely.
#
# modules/compute/gke/main.tf's `enable_binary_authorization` var wires
# each cluster to actually enforce this policy — a project policy alone
# does nothing until a cluster opts in via
# `binary_authorization.evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"`.

resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = var.evaluation_mode
    enforcement_mode = var.enforcement_mode
    require_attestations_by = (
      var.evaluation_mode == "REQUIRE_ATTESTATION" ? var.require_attestations_by : null
    )
  }

  global_policy_evaluation_mode = var.global_policy_evaluation_mode
}
