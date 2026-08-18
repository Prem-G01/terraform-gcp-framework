# Project-level org policy constraints — the zero-trust backstop behind
# config/global/security.yaml's validation rules. Those rules only catch
# what's written IN deployment.yaml before a plan runs; these are enforced
# by GCP itself against every API call to this project, including a
# direct console/gcloud change that bypasses this framework's pipeline
# entirely. See docs/security.md "Org policy constraints".
#
# Every constraint here defaults to enforced — this module exists so a
# deployment can loosen one deliberately, as a reviewable deployment.yaml
# diff, rather than the guardrail simply not existing. Each is its own
# resource (not a for_each over a generic map) because boolean and list
# constraints have genuinely different `spec.rules` shapes — see the
# comments below.

# --- Boolean constraints: spec.rules.enforce = "TRUE" -----------------

resource "google_org_policy_policy" "disable_sa_key_creation" {
  count = var.disable_service_account_key_creation ? 1 : 0

  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "restrict_public_sql_ips" {
  count = var.restrict_public_sql_ips ? 1 : 0

  name   = "projects/${var.project_id}/policies/sql.restrictPublicIp"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "require_os_login" {
  count = var.require_os_login ? 1 : 0

  name   = "projects/${var.project_id}/policies/compute.requireOsLogin"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "skip_default_network_creation" {
  count = var.skip_default_network_creation ? 1 : 0

  name   = "projects/${var.project_id}/policies/compute.skipDefaultNetworkCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# --- List constraint: deny every value, no exceptions ------------------

resource "google_org_policy_policy" "restrict_vm_external_ips" {
  count = var.restrict_vm_external_ips ? 1 : 0

  name   = "projects/${var.project_id}/policies/compute.vmExternalIpAccess"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}
