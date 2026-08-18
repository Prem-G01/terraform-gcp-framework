"""Security / governance validation.

Rule *conditions* live here in Python (there's no generic policy DSL — see
docs/security.md for why that trade-off was made). Rule *severity* and
*description* come from config/global/security.yaml, so a reviewer can
downgrade a rule from ERROR to WARNING (or vice versa) without touching
code. Unknown/removed rule ids fall back to ERROR so a typo in the policy
file can't silently disable a check.
"""

from __future__ import annotations

from engine.errors import Finding

OPEN_CIDR = "0.0.0.0/0"


def _severity(security_policy: dict, rule_id: str) -> str:
    for rule in security_policy.get("rules", []):
        if rule.get("id") == rule_id:
            return rule.get("severity", "ERROR")
    return "ERROR"


def _has_port(allow_rules: list, port: str) -> bool:
    for rule in allow_rules or []:
        ports = rule.get("ports")
        if ports is None:
            return True  # no ports = all ports for this protocol
        if port in [str(p) for p in ports]:
            return True
    return False


def validate_security(deployment) -> list[Finding]:
    policy = deployment.global_config.security
    findings: list[Finding] = []
    enabled = set(deployment.enabled_resource_types())

    if "firewall" in enabled:
        for name, fw in deployment.instances("firewall").items():
            source_ranges = fw.get("source_ranges") or []
            if fw.get("direction", "INGRESS") == "INGRESS" and OPEN_CIDR in source_ranges:
                allow = fw.get("allow") or []
                if _has_port(allow, "22"):
                    findings.append(_finding(policy, "SEC_PUBLIC_SSH", f"firewall.{name}",
                                              f"Ingress from {OPEN_CIDR} allows TCP/22 (SSH)."))
                if _has_port(allow, "3389"):
                    findings.append(_finding(policy, "SEC_PUBLIC_RDP", f"firewall.{name}",
                                              f"Ingress from {OPEN_CIDR} allows TCP/3389 (RDP)."))
                if any(r.get("ports") is None for r in allow):
                    findings.append(_finding(policy, "SEC_FIREWALL_OPEN_INGRESS", f"firewall.{name}",
                                              f"Ingress from {OPEN_CIDR} allows a protocol with no port restriction."))

    if "vm" in enabled:
        for name, vm in deployment.instances("vm").items():
            if (vm.get("network") or {}).get("public_ip"):
                findings.append(_finding(policy, "SEC_PUBLIC_VM", f"vm.{name}",
                                          "network.public_ip is true; VMs must stay on private IPs and use IAP/Cloud NAT."))
            oslogin = (vm.get("metadata") or {}).get("enable-oslogin")
            if str(oslogin).upper() != "TRUE":
                findings.append(_finding(policy, "SEC_MISSING_OS_LOGIN", f"vm.{name}",
                                          "metadata['enable-oslogin'] must be \"TRUE\"."))
            shielded = vm.get("shielded_vm") or {}
            if not (shielded.get("secure_boot") and shielded.get("vtpm") and shielded.get("integrity_monitoring")):
                findings.append(_finding(policy, "SEC_MISSING_SHIELDED_VM", f"vm.{name}",
                                          "shielded_vm.secure_boot, vtpm, and integrity_monitoring must all be true."))

    if "service_accounts" in enabled:
        for name, sa in deployment.instances("service_accounts").items():
            broad = [r for r in (sa.get("roles") or []) if r in ("roles/owner", "roles/editor") or r.endswith(".admin")]
            if broad:
                findings.append(_finding(policy, "SEC_OVERPRIVILEGED_SERVICE_ACCOUNT", f"service_accounts.{name}",
                                          f"Grants broad role(s): {', '.join(broad)}."))

    if "buckets" in enabled:
        for name, bucket in deployment.instances("buckets").items():
            if bucket.get("public_access_prevention") != "enforced" or not bucket.get("uniform_bucket_level_access"):
                findings.append(_finding(policy, "SEC_PUBLIC_BUCKET", f"buckets.{name}",
                                          "public_access_prevention must be 'enforced' and uniform_bucket_level_access must be true."))

    if "cloudsql" in enabled:
        for name, sql in deployment.instances("cloudsql").items():
            if (sql.get("network") or {}).get("ipv4_enabled"):
                findings.append(_finding(policy, "SEC_PUBLIC_SQL", f"cloudsql.{name}",
                                          "network.ipv4_enabled is true; Cloud SQL must stay on a private IP."))
            if not sql.get("deletion_protection", True):
                findings.append(_finding(policy, "SEC_SQL_NO_DELETION_PROTECTION", f"cloudsql.{name}",
                                          "deletion_protection is false."))

    if "kms" in enabled:
        for name, kr in deployment.instances("kms").items():
            for key_name, key in (kr.get("keys") or {}).items():
                if not key.get("rotation_period"):
                    findings.append(_finding(policy, "SEC_KMS_ROTATION_MISSING", f"kms.{name}.{key_name}",
                                              "No rotation_period set on this crypto key."))

    if "secrets" in enabled:
        min_length = deployment.global_config.defaults.get("security_defaults", {}).get("secrets", {}).get("min_length", 16)
        for name, secret in deployment.instances("secrets").items():
            if secret.get("length", 0) < min_length:
                findings.append(_finding(policy, "SEC_SECRET_TOO_SHORT", f"secrets.{name}",
                                          f"length {secret.get('length')} is below the required minimum of {min_length}."))

    if "gke" in enabled:
        for name, cluster in deployment.instances("gke").items():
            if not (cluster.get("private_cluster") or {}).get("enable_private_nodes", True):
                findings.append(_finding(policy, "SEC_GKE_PUBLIC_CLUSTER", f"gke.{name}",
                                          "private_cluster.enable_private_nodes is false."))

    if "memorystore" in enabled:
        for name, cache in deployment.instances("memorystore").items():
            if not cache.get("auth_enabled", True):
                findings.append(_finding(policy, "SEC_REDIS_AUTH_DISABLED", f"memorystore.{name}",
                                          "auth_enabled is false."))
            if cache.get("transit_encryption_mode") == "DISABLED":
                findings.append(_finding(policy, "SEC_REDIS_UNENCRYPTED_TRANSIT", f"memorystore.{name}",
                                          "transit_encryption_mode is DISABLED."))

    if "cloudfunctions" in enabled:
        for name, fn in deployment.instances("cloudfunctions").items():
            if fn.get("ingress_settings") == "ALLOW_ALL":
                findings.append(_finding(policy, "SEC_CLOUDFUNCTION_PUBLIC_INGRESS", f"cloudfunctions.{name}",
                                          "ingress_settings is ALLOW_ALL — this function is publicly reachable."))

    return findings


def _finding(policy: dict, rule_id: str, resource: str, message: str) -> Finding:
    return Finding(
        severity=_severity(policy, rule_id),
        category="security",
        rule=rule_id,
        resource=resource,
        message=message,
    )
