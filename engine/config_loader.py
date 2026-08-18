"""Loads config/global/*.yaml + one config/environments/<env>/deployment.yaml
and merges them into a single normalized structure.

Merge order (lowest to highest precedence):
  1. config/global/defaults.yaml  resource_defaults[<type>]
  2. the resource instance itself, from deployment.yaml
Global policy (security, naming, regions, dependencies, labels) is never
merged into the deployment — it stays separate and is applied by the other
engine/*.py modules directly, so it can never be silently overridden by an
environment's deployment.yaml.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


class ConfigError(Exception):
    """Raised for YAML syntax errors or a missing/unreadable config file."""


def _load_yaml(path: Path) -> dict:
    if not path.is_file():
        raise ConfigError(f"Config file not found: {path}")
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        raise ConfigError(f"Invalid YAML syntax in {path}: {exc}") from exc
    return data or {}


def _interpolate(value: Any, tokens: dict[str, str]) -> Any:
    """Replaces {project_id}/{region}/{environment}/{owner} tokens in every
    string under `value`. Plain literal substring replace, not str.format —
    deliberately, so a string like a Workflows source body containing
    unrelated `{...}` runtime syntax (e.g. `$${message}`) is left alone
    instead of raising or being mis-substituted."""
    if isinstance(value, str):
        for token, replacement in tokens.items():
            if replacement:
                value = value.replace(f"{{{token}}}", replacement)
        return value
    if isinstance(value, dict):
        return {k: _interpolate(v, tokens) for k, v in value.items()}
    if isinstance(value, list):
        return [_interpolate(v, tokens) for v in value]
    return value


def deep_merge(base: Any, override: Any) -> Any:
    """Recursively merge `override` on top of `base`. Dicts merge key by
    key; any other type (including lists) is replaced wholesale by
    `override` when present — lists are never concatenated, to keep merge
    behavior predictable for engineers reading a deployment.yaml."""
    if isinstance(base, dict) and isinstance(override, dict):
        result = dict(base)
        for key, value in override.items():
            result[key] = deep_merge(base.get(key), value) if key in base else value
        return result
    return override if override is not None else base


@dataclass
class GlobalConfig:
    defaults: dict
    naming: dict
    labels: dict
    regions: dict
    security: dict
    dependencies: dict

    @classmethod
    def load(cls, config_root: Path) -> "GlobalConfig":
        g = config_root / "global"
        return cls(
            defaults=_load_yaml(g / "defaults.yaml"),
            naming=_load_yaml(g / "naming.yaml"),
            labels=_load_yaml(g / "labels.yaml"),
            regions=_load_yaml(g / "regions.yaml"),
            security=_load_yaml(g / "security.yaml"),
            dependencies=_load_yaml(g / "dependencies.yaml"),
        )


@dataclass
class Deployment:
    path: Path
    raw: dict
    normalized: dict
    global_config: GlobalConfig

    @property
    def environment(self) -> str:
        return self.raw.get("metadata", {}).get("environment", "")

    @property
    def region(self) -> str:
        return self.raw.get("region", {}).get("primary", "")

    @property
    def resources(self) -> dict:
        return self.normalized.get("resources", {})

    def enabled_resource_types(self) -> list[str]:
        return [
            rtype
            for rtype, block in self.resources.items()
            if isinstance(block, dict) and block.get("enabled")
        ]

    def instances(self, resource_type: str) -> dict:
        block = self.resources.get(resource_type, {})
        return block.get("instances", {}) if isinstance(block, dict) else {}


def load_deployment(env_dir: Path, config_root: Path | None = None) -> Deployment:
    """env_dir: config/environments/<env>/  (must contain deployment.yaml)"""
    env_dir = Path(env_dir)
    if config_root is None:
        # config/environments/<env> -> config/
        config_root = env_dir.parent.parent

    global_config = GlobalConfig.load(config_root)
    raw = _load_yaml(env_dir / "deployment.yaml")

    normalized = copy.deepcopy(raw)
    resource_defaults = global_config.defaults.get("resource_defaults", {})
    environment = raw.get("metadata", {}).get("environment", "")
    owner = raw.get("metadata", {}).get("owner") or global_config.defaults.get("organization", {}).get("owner", "")

    # {project_id}/{region}/{environment}/{owner} tokens anywhere under
    # `resources` are resolved from the values declared once at the top of
    # this same file — see docs/configuration.md "Avoiding duplication
    # inside a deployment.yaml". Applied before the resource_defaults merge
    # so a default value can also use these tokens.
    tokens = {
        "project_id": raw.get("project", {}).get("id", ""),
        "region": raw.get("region", {}).get("primary", ""),
        "environment": environment,
        "owner": owner,
    }
    if "resources" in normalized:
        normalized["resources"] = _interpolate(normalized["resources"], tokens)

    for rtype, block in normalized.get("resources", {}).items():
        if not isinstance(block, dict):
            continue
        instances = block.get("instances")
        if not isinstance(instances, dict):
            continue
        type_defaults = resource_defaults.get(rtype, {})
        for name, instance in list(instances.items()):
            merged = deep_merge(type_defaults, instance) if type_defaults else instance
            merged = _apply_required_labels(merged, global_config, environment, owner)
            instances[name] = merged

    return Deployment(path=env_dir, raw=raw, normalized=normalized, global_config=global_config)


def _apply_required_labels(instance: Any, global_config: GlobalConfig, environment: str, owner: str) -> Any:
    if not isinstance(instance, dict) or "labels" not in instance:
        return instance
    required = global_config.labels.get("labels", {}).get("required", {})
    resolved = {
        k: v.format(environment=environment, owner=owner) if isinstance(v, str) else v
        for k, v in required.items()
    }
    instance = dict(instance)
    instance["labels"] = {**resolved, **(instance.get("labels") or {})}
    return instance


def discover_environments(config_root: Path) -> list[Path]:
    env_root = Path(config_root) / "environments"
    if not env_root.is_dir():
        return []
    return sorted(p for p in env_root.iterdir() if p.is_dir() and (p / "deployment.yaml").is_file())
