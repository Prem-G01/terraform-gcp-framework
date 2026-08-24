# Real name generation, not just a separator/company pass-through — see
# docs/configuration.md "Generated names". Found 2026-08-24: this module
# was instantiated in platform/main.tf but nothing referenced its outputs
# anywhere, and it never actually implemented config/global/naming.yaml's
# `pattern` templates despite naming.yaml's own header comment claiming it
# did. Scoped to exactly the resource types naming.yaml defines a
# dedicated pattern for (`vm`, `sql`) — `default`/`project` remain
# genuinely unused: `project` has no Terraform-managed consumer (this
# platform never creates a GCP project via Terraform), and wiring
# `default` into the other ~30 resource types is real, separate,
# unscoped work, not implied by what was actually asked to fix here.

locals {

  separator = var.naming.separator

  company = var.organization.company

  # For each pattern key (e.g. "vm", "sql") and each instance key needing
  # a generated name under that pattern, interpolate
  # naming.yaml's pattern.<key> template. {service} is deliberately not
  # substituted here — neither the vm nor sql pattern uses it, and no
  # resource type using the {service}-bearing "default" pattern is wired
  # into var.instance_keys yet (see the module header comment above).
  #
  # Wrapped in lower() — found 2026-08-24 against a real GCP plan:
  # organization.company in config/global/defaults.yaml is "DG"
  # (uppercase), and google_compute_instance.name must match
  # `^[a-z]([-a-z0-9]*[a-z0-9])?$` (lowercase only, real provider-side
  # regex — the plan failed outright with "DG-dev-vm-app-vm-01" before
  # this). Cloud SQL instance names allow mixed case, so that one plans
  # fine either way, but lowercasing unconditionally matches naming.yaml's
  # own allowed_characters.default regex (also lowercase-only) and is
  # correct for every resource type this could ever generate a name for.
  generated_names = {
    for pattern_key, keys in var.instance_keys : pattern_key => {
      for k in keys : k => lower(replace(
        replace(
          replace(
            lookup(var.naming.pattern, pattern_key, var.naming.pattern.default),
            "{company}", local.company
          ),
          "{environment}", var.environment
        ),
        "{name}", k
      ))
    }
  }

}
