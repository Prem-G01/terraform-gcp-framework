resource "google_compute_global_address" "ip" {

  for_each = var.config.load_balancer

  project = var.project_id

  name = "${each.key}-ip"

}

resource "google_compute_region_network_endpoint_group" "neg" {

  for_each = {

    for k, v in var.config.load_balancer :

    k => v

    if v.backend.type == "CLOUD_RUN"

  }



  project = var.project_id

  name = "${each.key}-neg"

  region = each.value.region



  network_endpoint_type = "SERVERLESS"



  cloud_run {

    service = each.value.backend.service

  }

}

resource "google_compute_backend_service" "backend" {

  for_each = var.config.load_balancer



  project = var.project_id



  name = "${each.key}-backend"



  protocol = "HTTP"



  timeout_sec = lookup(

    each.value,

    "timeout_sec",

    30

  )



  backend {

    group = google_compute_region_network_endpoint_group.neg[

      each.key

    ].id

  }

}

# --- SSL / HTTPS (optional, driven by config.<name>.ssl.enabled) ---------

locals {
  ssl_enabled = {
    for k, v in var.config.load_balancer :
    k => lookup(lookup(v, "ssl", {}), "enabled", false)
  }
  ssl_lbs = { for k, v in var.config.load_balancer : k => v if local.ssl_enabled[k] }
}

resource "google_compute_managed_ssl_certificate" "cert" {

  for_each = local.ssl_lbs

  project = var.project_id
  name    = "${each.key}-cert"

  managed {
    domains = each.value.ssl.domains
  }
}

resource "google_compute_target_https_proxy" "https_proxy" {

  for_each = local.ssl_lbs

  project = var.project_id
  name    = "${each.key}-https-proxy"

  url_map = google_compute_url_map.urlmap[each.key].id

  ssl_certificates = [
    google_compute_managed_ssl_certificate.cert[each.key].id
  ]
}

resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {

  for_each = local.ssl_lbs

  project = var.project_id
  name    = "${each.key}-https"

  ip_address = google_compute_global_address.ip[each.key].id
  port_range = "443"

  target = google_compute_target_https_proxy.https_proxy[each.key].id
}

# --- HTTP: serves traffic directly when SSL is disabled, otherwise ---------
# --- redirects every request to HTTPS. -------------------------------------

resource "google_compute_url_map" "urlmap" {

  for_each = var.config.load_balancer



  project = var.project_id



  name = "${each.key}-urlmap"



  default_service = local.ssl_enabled[each.key] ? null : google_compute_backend_service.backend[

    each.key

  ].id

  dynamic "default_url_redirect" {
    for_each = local.ssl_enabled[each.key] ? [1] : []
    content {
      https_redirect = true
      strip_query    = false
    }
  }

}

resource "google_compute_target_http_proxy" "proxy" {

  for_each = var.config.load_balancer



  project = var.project_id



  name = "${each.key}-proxy"



  url_map = google_compute_url_map.urlmap[

    each.key

  ].id

}

resource "google_compute_global_forwarding_rule" "forwarding_rule" {

  for_each = var.config.load_balancer



  project = var.project_id



  name = "${each.key}-http"



  ip_address = google_compute_global_address.ip[

    each.key

  ].id



  port_range = "80"



  target = google_compute_target_http_proxy.proxy[

    each.key

  ].id

}
