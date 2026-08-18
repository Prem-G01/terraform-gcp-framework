"""Proves {project_id}/{region}/{environment}/{owner} token interpolation —
the fix for engineers having to retype the same region/project id string in
every resource block instead of declaring it once at the top of
deployment.yaml (see docs/configuration.md "Avoiding duplication inside a
deployment.yaml").
"""

from conftest import CONFIG_ROOT
from engine import config_loader


def test_interpolate_replaces_known_tokens():
    tokens = {"project_id": "prj-x", "region": "asia-south1", "environment": "dev", "owner": "devops"}
    value = {
        "zone": "{region}-a",
        "nested": {"bucket": "{project_id}-{environment}-app"},
        "list": ["{region}", "static-value"],
    }
    result = config_loader._interpolate(value, tokens)
    assert result["zone"] == "asia-south1-a"
    assert result["nested"]["bucket"] == "prj-x-dev-app"
    assert result["list"] == ["asia-south1", "static-value"]


def test_interpolate_leaves_unrelated_braces_alone():
    """A Workflows source body (or anything else) using `{...}` for its own
    runtime templating must not be touched — only the four known tokens
    are ever substituted, via literal replace, not str.format."""
    tokens = {"project_id": "prj-x", "region": "", "environment": "", "owner": ""}
    value = "main:\n  return: $${message}\n"
    assert config_loader._interpolate(value, tokens) == value


def test_real_dev_config_resolves_tokens_to_real_values():
    d = config_loader.load_deployment(CONFIG_ROOT / "environments" / "dev", CONFIG_ROOT)
    vm = d.instances("vm")["app-vm-01"]
    subnet = d.instances("subnet")["app-subnet"]
    bucket = d.instances("buckets")["app-storage"]
    function_source_bucket = d.instances("cloudfunctions")["process-upload"]["source"]["bucket"]

    assert vm["zone"] == "asia-south1-a"
    assert subnet["region"] == "asia-south1"
    assert bucket["name"] == "prj-dg-devops-test-dev-app-storage"
    # Proves the DRY win: the function's source bucket reference resolves
    # to the exact same computed name as the bucket resource itself,
    # without either one spelling out the literal project id twice.
    assert function_source_bucket == bucket["name"]


def test_no_unresolved_tokens_remain_in_normalized_config():
    """A leftover literal "{something}" in the rendered config would mean a
    typo'd token name (e.g. {enviroment}) silently passed through instead
    of resolving — this catches that class of mistake."""
    import json

    d = config_loader.load_deployment(CONFIG_ROOT / "environments" / "dev", CONFIG_ROOT)
    serialized = json.dumps(d.normalized)
    assert "{project_id}" not in serialized
    assert "{region}" not in serialized
    assert "{environment}" not in serialized
    assert "{owner}" not in serialized
