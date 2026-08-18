# GCP Infrastructure Platform

A YAML-driven, validated, centrally-executed Terraform platform for Google
Cloud. One engineer-facing input — `config/environments/<env>/deployment.yaml`
— drives 33 resource types across a reusable module set, gated by a
validation engine that runs before Terraform ever sees the config.

## What this is

```
config/environments/dev/deployment.yaml   <- the ONE file you edit
        │
        ▼
python -m engine.cli validate             <- schema + dependency + security +
        │                                     naming + region + cost checks
        ▼ (only if it passes)
python -m engine.cli render                <- writes a normalized JSON artifact
        │
        ▼
terraform plan / apply                     <- platform/ reads ONLY that artifact
  (environments/<env>/ + platform/)
```

See [docs/architecture.md](docs/architecture.md) for the full picture and
[docs/configuration.md](docs/configuration.md) for the YAML reference.

## Repository layout

```
config/
  global/              org-wide policy: defaults, naming, labels, regions,
                        security rules, dependency graph, cost thresholds
  environments/         one deployment.yaml per environment (dev/sit/uat/prod)
  schema/                JSON Schema for deployment.yaml

engine/                 Python validation/dependency/security/naming/region/
                        cost/hardcode engine + CLI (no GCP API calls)

modules/                 reusable, environment-agnostic Terraform modules
                        (one per GCP resource type, e.g. modules/compute/vm)

platform/               the orchestration root — one `module` block per
                        resource type, count-gated by deployment.yaml

environments/<env>/     ~10-line thin stack per environment: backend +
                        provider + `module "platform" { source = "../../platform" }`

bootstrap/               one-time stack: remote state bucket, artifact bucket,
                        CI/CD service accounts, optional Workload Identity
                        Federation — NOT applied by default, see docs/state-management.md

.github/workflows/      GitHub Actions pipelines (plan-on-PR, approve-then-apply)

tests/                  pytest suite for the validation engine (proves both
                        valid and invalid config are handled correctly)

docs/                   architecture, configuration, validation, dependencies,
                        security, service-accounts, state-management, cicd,
                        logging, modules, testing, troubleshooting

archive/                everything removed from the previous version of this
                        repo, kept (not deleted) in case anything in it turns
                        out to still be needed — see archive/legacy-dev-2026-08-18/
```

## Quickstart — deploy dev

```bash
# 1. Validate + render the config (fails fast, never touches GCP)
python -m engine.cli validate config/environments/dev
python -m engine.cli render config/environments/dev \
  --out environments/dev/.generated/deployment.normalized.json

# 2. Plan (needs bootstrap to have been run once — see docs/state-management.md)
cd environments/dev
terraform init -backend-config="bucket=<state bucket>" -backend-config="prefix=dev"
terraform plan
```

In CI/CD this is exactly what `.github/workflows/plan.yml` runs on every
PR; `apply.yml` runs the same validate+render, then applies, gated by a
required reviewer on the target GitHub Environment. See
[docs/cicd.md](docs/cicd.md).

## Adding or changing infrastructure

Edit `config/environments/<env>/deployment.yaml` — flip a resource type's
`enabled`, add an instance under it, or change a field. Never edit
`platform/` or `modules/` for a routine change. Run
`python -m engine.cli validate config/environments/<env>` before opening a
PR; CI runs it again regardless.

Adding a whole new resource *type* (one Terraform doesn't yet support) is a
platform change, not a config change — see
[docs/modules.md](docs/modules.md) "Adding a new module".

## Running the tests

```bash
pip install -r engine/requirements.txt
pytest tests/ -v                          # validation engine: 14 tests
terraform fmt -check -recursive .          # style
python -m engine.cli hardcode-scan .       # zero-hardcode gate
python -m engine.cli validate-all config   # every environment
```

## Honest limitations

This rebuild is code-complete but was deliberately **not applied against
real GCP infrastructure** — see
[docs/troubleshooting.md "What this rebuild did and did not do"](docs/troubleshooting.md)
for the full, unvarnished list before calling anything here "production
ready."
