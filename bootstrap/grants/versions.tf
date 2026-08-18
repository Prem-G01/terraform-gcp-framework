terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.37"
    }
  }

  # Deliberately local, same reasoning as bootstrap/versions.tf — this
  # stack is applied by a human directly against a spoke project (sit/uat/
  # prod), not through the environment's own remote-state pipeline. Run
  # once per spoke project; see docs/service-accounts.md "Cross-project
  # access".
  backend "local" {
    path = "terraform.tfstate.grants"
  }
}
