module "platform" {
  source = "../../platform"

  project_id      = var.project_id
  environment     = var.environment
  deployment_file = "${path.module}/.generated/deployment.normalized.json"
}
