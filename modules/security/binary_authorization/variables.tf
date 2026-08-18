variable "project_id" {
  type = string
}

variable "evaluation_mode" {
  description = "ALWAYS_DENY (block every image — the safe starting point until real attestors exist), REQUIRE_ATTESTATION (only images signed by require_attestations_by), or ALWAYS_ALLOW (policy exists but enforces nothing — effectively off, useful only mid-rollout)."
  type        = string
  default     = "ALWAYS_DENY"

  validation {
    condition     = contains(["ALWAYS_DENY", "REQUIRE_ATTESTATION", "ALWAYS_ALLOW"], var.evaluation_mode)
    error_message = "evaluation_mode must be ALWAYS_DENY, REQUIRE_ATTESTATION, or ALWAYS_ALLOW."
  }
}

variable "require_attestations_by" {
  description = <<-EOT
    Full resource names of existing google_binary_authorization_attestor
    resources (e.g. "projects/<id>/attestors/<name>"), required when
    evaluation_mode = REQUIRE_ATTESTATION. Deliberately NOT created by
    this module — a real attestor needs real cryptographic signing key
    material tied to your org's actual build pipeline (Cloud Build, or
    whatever CI produces the image); fabricating placeholder key material
    here would be security theater, not security. Create attestors
    separately once you have a real signer, then pass their names in.
  EOT
  type        = list(string)
  default     = []
}

variable "enforcement_mode" {
  description = "ENFORCED_BLOCK_AND_AUDIT_LOG actually blocks a non-compliant deploy. DRYRUN_AUDIT_LOG_ONLY logs what would have been blocked without blocking it — use this first, to see what the policy would catch before it can break a real deploy."
  type        = string
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"

  validation {
    condition     = contains(["ENFORCED_BLOCK_AND_AUDIT_LOG", "DRYRUN_AUDIT_LOG_ONLY"], var.enforcement_mode)
    error_message = "enforcement_mode must be ENFORCED_BLOCK_AND_AUDIT_LOG or DRYRUN_AUDIT_LOG_ONLY."
  }
}

variable "global_policy_evaluation_mode" {
  description = "ENABLE also trusts Google-curated base images (GKE system images, etc.) that Google itself attests — without this, the platform's own GKE control plane images could get blocked by an otherwise-correct ALWAYS_DENY/REQUIRE_ATTESTATION policy."
  type        = string
  default     = "ENABLE"
}
