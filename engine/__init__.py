"""Validation/dependency/security/naming engine for the GCP Terraform platform.

Everything here is pure Python with no GCP API calls — it only reads
config/global/*.yaml and config/environments/<env>/deployment.yaml and
decides, before Terraform ever runs, whether the deployment is allowed to
proceed. See docs/validation.md for the pipeline this package implements.
"""

REPO_ROOT_MARKERS = ("config", "modules", "platform")
