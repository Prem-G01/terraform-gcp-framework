provider "google" {
  project = var.project_id
  region  = var.region

  # See environments/dev/provider.tf for why these two lines are needed
  # — a human running this via Application Default Credentials (this
  # stack is always run by a human directly, never CI — see main.tf's
  # header comment) otherwise hits real quota-project errors on APIs
  # like Org Policy. bootstrap/main.tf itself doesn't touch Org Policy,
  # but bootstrap/grants/main.tf and every environments/*/provider.tf do,
  # and this stack is the first one a human runs — found missing here by
  # a code review after being added everywhere else, once bootstrap
  # itself needs an API sensitive to this (or once GCP adds one that
  # wasn't sensitive before), it would otherwise fail the exact same way.
  user_project_override = true
  billing_project       = var.project_id
}
