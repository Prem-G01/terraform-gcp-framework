terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.37"
    }
  }

  # Deliberately local. This stack CREATES the GCS bucket every other
  # stack's remote state lives in — it can't depend on that bucket already
  # existing. Run once per project, by a human, from a workstation with
  # org-level permissions; see docs/state-management.md "Bootstrapping".
  # The resulting terraform.tfstate.bootstrap file is sensitive (it
  # contains the plan/apply service accounts) — store it in the artifact
  # bucket after the first successful apply, then treat this directory's
  # local state as a cold-start fallback only.
  backend "local" {
    path = "terraform.tfstate.bootstrap"
  }
}
