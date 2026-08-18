# Every value here is read straight out of config/environments/dev/deployment.yaml
# by the render step — nothing below is hardcoded, it's re-derived from the
# same JSON platform/ reads. Kept as plain variables (not re-parsed from
# YAML a second time) so `terraform plan -var-file=...` still works for a
# human running this by hand outside the CLI wrapper.

variable "project_id" {
  type    = string
  default = "prj-dg-devops-test"
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "environment" {
  type    = string
  default = "dev"
}
