provider "google" {
  project = var.project_id
  region  = var.region

  # See environments/dev/provider.tf for why these two lines are needed
  # — a human running this via Application Default Credentials otherwise
  # hits real quota-project errors on APIs like Org Policy.
  user_project_override = true
  billing_project       = var.project_id
}
