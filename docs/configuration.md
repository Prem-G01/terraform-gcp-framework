# Configuration reference

## Single source of truth

```
config/
  global/
    defaults.yaml        organization identity, security_defaults, labels_defaults,
                          resource_defaults (fields applied only when an instance omits them)
    naming.yaml           naming engine rules (pattern, max_length, allowed_characters, reserved_words)
    labels.yaml            required label keys + default tags
    regions.yaml            approved regions/zones
    security.yaml           security rule catalogue (id, applies_to, severity, description)
    dependencies.yaml       resource-type dependency graph
    cost.yaml               static cost tables + per-environment warning thresholds
  environments/
    dev/deployment.yaml
    sit/deployment.yaml
    uat/deployment.yaml
    prod/deployment.yaml
  schema/
    deployment.schema.json  structural JSON Schema for deployment.yaml
```

Global policy (`config/global/`) is never overridable from a
`deployment.yaml` — there is no merge path that lets an environment weaken
a security rule or add an unapproved region. If you need to change policy,
change `config/global/`, which applies to every environment identically.

## deployment.yaml shape

```yaml
apiVersion: platform.gcp/v1
kind: Deployment
metadata:
  name: application-platform
  environment: dev              # dev | sit | uat | prod
  owner: devops
project:
  id: prj-dg-devops-test
region:
  primary: asia-south1
resources:
  <resource_type>:
    enabled: true|false
    instances:
      <instance_name>:
        <fields specific to that resource type>
```

`resources.apis` is the one exception — it takes `services: [...]` instead
of `instances`. Every other resource type follows the `enabled` +
`instances` shape. See
`config/environments/dev/deployment.yaml` for a fully populated example
covering all 25 supported types, and
`config/environments/sit/deployment.yaml` for the minimal template used to
start a new environment.

## Merge order (lowest to highest precedence)

1. `config/global/defaults.yaml` → `resource_defaults[<type>]` — applied
   only to fields the instance omits (see `engine/config_loader.deep_merge` —
   dicts merge key-by-key, lists are replaced wholesale, never concatenated).
2. The instance itself, from `deployment.yaml`.
3. Required labels from `config/global/labels.yaml` are added to any
   instance that already declares a `labels:` block (environment and owner
   tokens resolved from `metadata`).

This merge happens once, in `engine/config_loader.load_deployment`, and its
result — `Deployment.normalized` — is what `engine/cli.py render` writes to
disk. Terraform never repeats this merge; see
[docs/modules.md](modules.md) "Where defaults actually get applied."

## Avoiding duplication inside a deployment.yaml

`project.id`, `region.primary`, `metadata.environment`, and `metadata.owner`
are declared once, at the top of the file. Anywhere else in `resources`,
reference them with `{project_id}`, `{region}`, `{environment}`, `{owner}`
instead of retyping the literal value — `engine/config_loader._interpolate`
resolves these before Terraform ever sees the config:

```yaml
project:
  id: prj-dg-devops-test
region:
  primary: asia-south1
resources:
  vm:
    instances:
      app-vm-01:
        zone: "{region}-a"        # -> "asia-south1-a"
  buckets:
    instances:
      app-storage:
        name: "{project_id}-{environment}-app-storage"
  cloudfunctions:
    instances:
      process-upload:
        source:
          bucket: "{project_id}-{environment}-app-storage"   # same bucket, same token — never drifts
```

**Quote it.** `zone: {region}-a` (unquoted) is invalid YAML — a bare `{`
starts a flow-mapping, not a string. Always write `"{region}-a"`.

This is a plain literal `str.replace`, not `str.format` — a string
containing unrelated `{...}` syntax (e.g. a Workflows `source_contents`
body using `$${message}`) is left untouched; only the four known token
names are ever substituted. `tests/test_interpolation.py` covers both the
substitution and that guarantee. If a rendered config still contains a
literal `{something}` after `render`, it's a typo'd token name (e.g.
`{enviroment}`) that silently didn't match — `test_no_unresolved_tokens
_remain_in_normalized_config` catches that class of mistake.

## Disabling a resource type

```yaml
resources:
  cloudsql:
    enabled: false
    instances: {}
```

A disabled type contributes nothing to `platform/main.tf`'s `count`-gated
module block — no resources are planned, and if any were previously
applied, the next `apply` destroys them (standard Terraform behavior for a
module whose `count` drops to 0). Anything that `requires` a disabled type
(see [docs/dependencies.md](dependencies.md)) fails validation before
Terraform ever runs.

## Adding a new environment

Copy `config/environments/sit/deployment.yaml` to
`config/environments/<new>/deployment.yaml`, set `metadata.environment` and
`project.id`, then create the matching `environments/<new>/` Terraform
stack (copy `environments/sit/`'s five files — none of them reference
"sit" except the `variables.tf` defaults and the `versions.tf`
backend-config comment).
