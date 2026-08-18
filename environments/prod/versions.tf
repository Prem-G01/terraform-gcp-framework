terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.37"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # terraform init -backend-config="bucket=<state bucket>" -backend-config="prefix=prod"
  backend "gcs" {}
}
