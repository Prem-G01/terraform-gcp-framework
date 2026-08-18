"""Unit tests for engine/live_cost.py's pure logic — shape parsing, SKU
matching, price extraction. No network access, no credentials: the one
function that actually calls the Cloud Billing Catalog API
(estimate_live_vm_hourly_rate) is exercised here with a pre-populated
skus_cache so it never reaches _list_skus. Keeps this file in the same
"pytest tests/ runs in under a second, no GCP call" category as
everything else under tests/ — see docs/validation.md "Cost validation".
"""

from engine import live_cost


def _sku(description, region, usage_type="OnDemand", units="0", nanos=0, sku_id="SKU-ID"):
    return {
        "skuId": sku_id,
        "description": description,
        "category": {"usageType": usage_type},
        "serviceRegions": [region],
        "pricingInfo": [
            {"pricingExpression": {"tieredRates": [{"unitPrice": {"units": units, "nanos": nanos}}]}}
        ],
    }


def test_parse_standard_shape_accepts_supported_families():
    assert live_cost._parse_standard_shape("e2-standard-4") == ("e2", 4)
    assert live_cost._parse_standard_shape("n2-standard-16") == ("n2", 16)


def test_parse_standard_shape_rejects_shared_core():
    assert live_cost._parse_standard_shape("e2-medium") is None
    assert live_cost._parse_standard_shape("e2-micro") is None
    assert live_cost._parse_standard_shape("e2-small") is None


def test_parse_standard_shape_rejects_custom_and_other_families():
    assert live_cost._parse_standard_shape("e2-custom-4-8192") is None
    assert live_cost._parse_standard_shape("m1-ultramem-40") is None
    assert live_cost._parse_standard_shape("not-a-machine-type") is None


def test_unit_price_usd_combines_units_and_nanos():
    sku = _sku("x", "asia-south1", units="2", nanos=500000000)
    assert live_cost._unit_price_usd(sku) == 2.5


def test_find_component_rate_matches_region_and_excludes_custom_and_preemptible():
    skus = [
        _sku("E2 Custom Instance Core running in Mumbai", "asia-south1", nanos=99000000, sku_id="wrong-custom"),
        _sku("Spot Preemptible E2 Instance Core running in Mumbai", "asia-south1", usage_type="Preemptible", nanos=1, sku_id="wrong-preemptible"),
        _sku("E2 Instance Core running in Los Angeles", "us-west2", nanos=26000000, sku_id="wrong-region"),
        _sku("E2 Instance Core running in Mumbai", "asia-south1", nanos=26199300, sku_id="right-one"),
    ]
    result = live_cost._find_component_rate(skus, "E2", "Core", "asia-south1")
    assert result is not None
    price, sku_id = result
    assert sku_id == "right-one"
    assert abs(price - 0.0261993) < 1e-9


def test_find_component_rate_returns_none_when_nothing_matches():
    skus = [_sku("N2 Instance Core running in Mumbai", "asia-south1", nanos=1)]
    assert live_cost._find_component_rate(skus, "E2", "Core", "asia-south1") is None


def test_estimate_live_vm_hourly_rate_computes_core_plus_ram():
    fake_skus = [
        _sku("E2 Instance Core running in Mumbai", "asia-south1", nanos=26199300, sku_id="core-sku"),
        _sku("E2 Instance Ram running in Mumbai", "asia-south1", nanos=3510720, sku_id="ram-sku"),
    ]
    cache = {live_cost.COMPUTE_ENGINE_SERVICE_ID: fake_skus}

    rate = live_cost.estimate_live_vm_hourly_rate("fake-token", "e2-standard-2", "asia-south1", cache)

    assert rate.vcpus == 2
    assert rate.ram_gb == 8
    assert rate.core_sku_id == "core-sku"
    assert rate.ram_sku_id == "ram-sku"
    expected = 2 * 0.0261993 + 8 * 0.0035107199999999997
    assert abs(rate.hourly_usd - expected) < 1e-6


def test_estimate_live_vm_hourly_rate_raises_for_shared_core_shape():
    cache = {live_cost.COMPUTE_ENGINE_SERVICE_ID: []}
    try:
        live_cost.estimate_live_vm_hourly_rate("fake-token", "e2-medium", "asia-south1", cache)
        assert False, "expected LiveCostError"
    except live_cost.LiveCostError as exc:
        assert "not a supported" in str(exc)


def test_estimate_live_vm_hourly_rate_raises_when_region_has_no_matching_sku():
    cache = {live_cost.COMPUTE_ENGINE_SERVICE_ID: []}
    try:
        live_cost.estimate_live_vm_hourly_rate("fake-token", "e2-standard-2", "asia-south1", cache)
        assert False, "expected LiveCostError"
    except live_cost.LiveCostError as exc:
        assert "No live" in str(exc)
