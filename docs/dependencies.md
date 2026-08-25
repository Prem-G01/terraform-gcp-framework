# Dependency engine

## Type-level graph

`config/global/dependencies.yaml` declares, for each resource type, which
other types must also be `enabled`:

```yaml
dependencies:
  subnet:
    requires: [vpc]
  vm:
    requires: [subnet, service_accounts]
  cloudsql:
    requires: [vpc, private_service_access, secrets]
  ...
```

This mirrors the `depends_on` chain that used to be hand-wired in the
original repo's single `Environment/dev/main.tf` — it's now data,
consulted by both the validation engine (blocks before `terraform plan`)
and mirrored in `platform/main.tf`'s `depends_on` lists (so Terraform's own
graph agrees, independent of the config check).

`engine.dependency_engine.validate_type_dependencies` walks this for every
`enabled` resource type in a deployment and fails if a required type isn't
also enabled. `validate_dependency_graph_integrity` separately checks the
graph itself for cycles (DFS with white/gray/black coloring) — this runs
regardless of which environment you're validating, since a cycle in the
graph would make dependency order undecidable for every deployment.
`tests/test_validation.py::test_real_dependency_graph_has_no_cycles`
asserts the real graph is acyclic; `test_dependency_cycle_is_detected`
proves the detector works against a synthetic cyclic graph.

## Instance-level references

Separately, `engine.dependency_engine.INSTANCE_REFERENCES` checks that a
field naming another instance actually resolves:

| Source type | Field | Must name an instance of |
|---|---|---|
| subnet | `vpc` | vpc |
| firewall | `network` | vpc |
| router | `network` | vpc |
| nat | `router` | router |
| private_service_access | `network` | vpc |
| vm | `subnet` | subnet |
| vm | `service_account.name` | service_accounts |
| cloudsql | `network.private_network` | vpc |
| cloudrun | `service_account.name` | service_accounts |
| load_balancer | `backend.service` | cloudrun |
| workflows | `service_account` | service_accounts |
| gke | `network` | vpc |
| gke | `subnet` | subnet |
| gke | `node_pool.service_account` | service_accounts |
| cloudfunctions | `service_account.name` | service_accounts |
| memorystore | `network` | vpc |
| iap | `target_vm` | vm |
| workload_identity | `gcp_service_account` | service_accounts |

A typo here (e.g. `subnet: "app-subnet"` when the real instance key is
`"app-subnets"`) fails with `INVALID_REFERENCE` and lists what instances
actually exist under the target type — this is the check that would have
caught it before Terraform's much less readable
`The given key does not exist` error at plan time.

### Nested instance references

`INSTANCE_REFERENCES` only expresses one reference per top-level instance
field. Some real references live inside a *nested* per-instance map
instead — found missing entirely on 2026-08-25, since neither is caught
by the table above:

| Source type | Nested collection | Field on each entry | Must name an instance of |
|---|---|---|---|
| cloudsql | `users` (keyed by username) | `password_secret` | secrets |
| pubsub | `subscriptions` (keyed by subscription name) | `dead_letter_policy.topic` | pubsub (another topic) |

`cloudsql.<instance>.users.<user>.password_secret` is a real
`var.passwords[secret_name]` lookup in
`modules/database/cloudsql/main.tf`; `pubsub.<instance>.subscriptions
.<sub>.dead_letter_policy.topic` is a real
`google_pubsub_topic.topic[...]` self-reference in
`modules/messaging/pubsub/main.tf`. Both crashed `terraform plan` with a
raw "Invalid index" error on a typo before this — `engine
.dependency_engine.NESTED_INSTANCE_REFERENCES` checks them the same way
`INSTANCE_REFERENCES` checks everything else, just walking one extra
level of nesting first.

## What this replaced

The original repo had no dependency engine at all — `Governance/
dependencies.yml` existed as a 0-byte placeholder file (see
`archive/legacy-dev-2026-08-18/empty-stubs/Governance/`). Ordering was
entirely implicit in hand-written `depends_on` lists in one 380-line root
`main.tf`, which is exactly the kind of thing that silently drifts out of
sync as resources get added.
