"""Live Cloud Billing Catalog lookup — the deliberate exception to
"engine/ makes zero GCP API calls" (see docs/validation.md "Cost
validation"). Every other file under engine/ is fast and credential-free
on purpose; this one genuinely needs network access and a Google identity
with default read access to the public Billing Catalog, and is invoked
as its own opt-in command (`python -m engine.cli cost-check-live`), never
from `validate`/`render`/CI.

Scope, stated honestly rather than pretended away:

- Only Compute Engine `*-standard-*` shapes (e2-standard-N, n2-standard-N,
  ...) get a real live rate. GCP prices these families from two
  per-region SKUs, matched here by `serviceRegions` (the actual region
  code, e.g. "asia-south1"), not by parsing the city name out of the
  description string. The description PREFIX genuinely differs per
  family though — "E2 Instance Core running in ...", but "N1
  *Predefined* Instance Core running in ..." and "N2D *AMD* Instance
  Core running in ..." — `_FAMILY_SKU_PREFIX` holds the real prefix per
  family, verified against the live API for asia-south1 rather than
  assumed uniform. vCPU/RAM counts for a `*-standard-N` shape follow each
  family's own fixed GB-per-vCPU ratio (`_FAMILY_RAM_PER_VCPU_GB` — 4 for
  E2/N2/N2D, 3.75 for N1, a real difference, not an approximation) rather
  than a hardcoded per-shape table, so this covers every size in a
  supported family, not just the ones this repo happens to use today.
- Shared-core shapes (e2-micro, e2-small, e2-medium), custom machine
  types, and highmem/highcpu families are NOT resolved live — their
  billing model doesn't map cleanly onto the two-SKU core+RAM formula
  above (shared-core types bill a fraction of a vCPU, not a whole one),
  and guessing would be worse than admitting the gap. They fall back to
  `config/global/cost.yaml`'s static table, same as before this module
  existed.
- Cloud SQL is not resolved live at all yet — its SKU shape differs
  again (edition/tier-specific, not a uniform core+RAM split across
  every tier) and was out of scope for this pass. Still static-only.
- This computes a *price* for any vCPU count in a supported family, not
  whether GCP actually offers that exact size — e.g. 'e2-standard-99'
  prices cleanly here even though no such real machine type exists.
  Shape existence is Compute Engine's problem at `terraform apply` time,
  not this tool's; it answers "what would N vCPUs of this family cost,"
  nothing more.
"""

from __future__ import annotations

from dataclasses import dataclass

CLOUD_BILLING_API = "https://cloudbilling.googleapis.com/v1"
COMPUTE_ENGINE_SERVICE_ID = "6F81-5844-456A"

# Real Cloud Billing Catalog description prefix per family — NOT uniform
# across families (verified against the live API for asia-south1; E2/N2
# are plain "<Family> Instance ...", N1 predefined shapes are "N1
# Predefined Instance ...", N2D is AMD-based and reads "N2D AMD Instance
# ..."). Getting this wrong doesn't raise an error — it just finds no
# match and silently falls back to the static table, so it's worth
# getting right rather than assuming a uniform pattern.
_FAMILY_SKU_PREFIX = {
    "e2": "E2 Instance",
    "n2": "N2 Instance",
    "n2d": "N2D AMD Instance",
    "n1": "N1 Predefined Instance",
}

# GCP's own fixed GB-per-vCPU ratio for every "<family>-standard-N"
# shape. NOT the same across families — N1 standard shapes are 3.75
# GB/vCPU, not 4 (e.g. n1-standard-4 = 4 vCPU / 15 GB). Getting this
# wrong doesn't error either — it silently over/under-prices the RAM
# component, which is worse than an honest fallback, so it's a per-
# family table rather than one constant.
_FAMILY_RAM_PER_VCPU_GB = {
    "e2": 4,
    "n2": 4,
    "n2d": 4,
    "n1": 3.75,
}

SUPPORTED_FAMILIES = tuple(_FAMILY_SKU_PREFIX)


@dataclass
class LiveRate:
    machine_type: str
    region: str
    vcpus: int
    ram_gb: float  # N1's 3.75 GB/vCPU ratio produces non-integer totals (e.g. n1-standard-1 = 3.75)
    hourly_usd: float
    core_sku_id: str
    ram_sku_id: str


class LiveCostError(RuntimeError):
    """Credentials, network, or API-shape problem — never silently swallowed."""


def _parse_standard_shape(machine_type: str) -> tuple[str, int] | None:
    """'e2-standard-4' -> ('e2', 4). None for anything not a *-standard-N shape."""
    parts = machine_type.split("-")
    if len(parts) != 3 or parts[1] != "standard":
        return None
    family = parts[0]
    if family not in SUPPORTED_FAMILIES:
        return None
    try:
        vcpus = int(parts[2])
    except ValueError:
        return None
    return family, vcpus


def get_access_token() -> str:
    """Application Default Credentials — the same identity `gcloud auth
    application-default login` sets up, or whatever a CI runner's
    Workload Identity Federation already provides. Deliberately not
    shelling out to the `gcloud` CLI: this needs to work in a bare CI
    container that has credentials but not the SDK installed.
    """
    try:
        import google.auth
        import google.auth.transport.requests
    except ImportError as exc:
        raise LiveCostError(
            "google-auth is required for live cost lookups (pip install google-auth) — "
            "not a dependency of the rest of engine/ on purpose, see this module's docstring."
        ) from exc

    try:
        credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform.read-only"]
        )
        credentials.refresh(google.auth.transport.requests.Request())
    except Exception as exc:  # noqa: BLE001 - surface whatever ADC failure actually happened
        raise LiveCostError(
            f"Could not obtain Application Default Credentials: {exc}. "
            "Run `gcloud auth application-default login` first."
        ) from exc
    return credentials.token


def _list_skus(token: str, service_id: str) -> list[dict]:
    try:
        import requests
    except ImportError as exc:
        raise LiveCostError("requests is required for live cost lookups (pip install requests)") from exc

    skus: list[dict] = []
    page_token = None
    headers = {"Authorization": f"Bearer {token}"}
    while True:
        params = {"pageSize": 5000}
        if page_token:
            params["pageToken"] = page_token
        resp = requests.get(f"{CLOUD_BILLING_API}/services/{service_id}/skus", headers=headers, params=params, timeout=30)
        if resp.status_code != 200:
            raise LiveCostError(f"Cloud Billing Catalog API returned {resp.status_code}: {resp.text[:500]}")
        data = resp.json()
        skus.extend(data.get("skus", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return skus


def _unit_price_usd(sku: dict) -> float:
    rate = sku["pricingInfo"][0]["pricingExpression"]["tieredRates"][0]["unitPrice"]
    return int(rate.get("units", 0)) + rate.get("nanos", 0) / 1e9


def _find_component_rate(skus: list[dict], sku_prefix: str, component: str, region: str) -> tuple[float, str] | None:
    """component: 'Core' or 'Ram'. sku_prefix: this family's real
    description prefix from _FAMILY_SKU_PREFIX, e.g. 'N1 Predefined
    Instance'. Matches OnDemand, non-preemptible, non-custom,
    non-sole-tenancy SKUs for the given region code."""
    prefix = f"{sku_prefix} {component} running in"
    for sku in skus:
        cat = sku.get("category", {})
        if cat.get("usageType") != "OnDemand":
            continue
        desc = sku.get("description", "")
        if not desc.startswith(prefix):
            continue
        if "Custom" in desc or "Sole Tenancy" in desc or "Premium" in desc:
            continue
        if region not in sku.get("serviceRegions", []):
            continue
        return _unit_price_usd(sku), sku["skuId"]
    return None


def estimate_live_vm_hourly_rate(token: str, machine_type: str, region: str, skus_cache: dict[str, list[dict]]) -> LiveRate:
    """Raises LiveCostError with a specific, honest reason on anything
    that isn't a supported *-standard-N shape or that the Catalog API
    doesn't have a matching SKU for — callers must not guess on failure.
    """
    parsed = _parse_standard_shape(machine_type)
    if parsed is None:
        raise LiveCostError(
            f"'{machine_type}' is not a supported *-standard-N shape for live pricing "
            f"(supported families: {', '.join(SUPPORTED_FAMILIES)}) — falling back to the static table."
        )
    family, vcpus = parsed
    sku_prefix = _FAMILY_SKU_PREFIX[family]

    if COMPUTE_ENGINE_SERVICE_ID not in skus_cache:
        skus_cache[COMPUTE_ENGINE_SERVICE_ID] = _list_skus(token, COMPUTE_ENGINE_SERVICE_ID)
    skus = skus_cache[COMPUTE_ENGINE_SERVICE_ID]

    core = _find_component_rate(skus, sku_prefix, "Core", region)
    ram = _find_component_rate(skus, sku_prefix, "Ram", region)
    if core is None or ram is None:
        raise LiveCostError(
            f"No live '{sku_prefix} .../Ram' SKU found for region '{region}' — "
            "either this region doesn't offer this family, or the Catalog API's naming changed."
        )

    core_rate, core_sku_id = core
    ram_rate, ram_sku_id = ram
    ram_gb = vcpus * _FAMILY_RAM_PER_VCPU_GB[family]
    hourly = vcpus * core_rate + ram_gb * ram_rate

    return LiveRate(
        machine_type=machine_type,
        region=region,
        vcpus=vcpus,
        ram_gb=ram_gb,
        hourly_usd=hourly,
        core_sku_id=core_sku_id,
        ram_sku_id=ram_sku_id,
    )
