locals {
  repository = split("/", var.repository)[1]
}

resource "azurerm_cdn_frontdoor_profile" "static_site_cdn_profile" {
  name                = "${var.name}-cdn-profile"
  resource_group_name = var.resource_group_name
  sku_name            = var.sku
}

# Azure FrontDoor Endpoint (currently uses the defaults as set by Azure)
resource "azurerm_cdn_frontdoor_endpoint" "static_site_endpoint" {
  name                     = "${var.name}-cdn-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.static_site_cdn_profile.id
}

# Azure FrontDoor Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "static_site_origin_group" {
  name                     = "${var.name}-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.static_site_cdn_profile.id
  session_affinity_enabled = true

  health_probe {
    interval_in_seconds = 100
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
}

resource "azurerm_cdn_frontdoor_origin" "static_site_origin" {
  name                           = "${var.name}-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.static_site_origin_group.id
  host_name                      = var.primary_web_host
  origin_host_header             = var.primary_web_host
  enabled                        = true
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "static_site_route" {
  name                          = "${var.name}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.static_site_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static_site_origin_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.static_site_origin.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.spa_ruleset.id]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]

}

resource "azurerm_cdn_frontdoor_rule_set" "spa_ruleset" {
  name                     = "SpaRuleset"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.static_site_cdn_profile.id
}


resource "azurerm_cdn_frontdoor_rule" "spa_rule" {
  depends_on                = [azurerm_cdn_frontdoor_origin_group.static_site_origin_group, azurerm_cdn_frontdoor_origin.static_site_origin]
  name                      = "SpaRule"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.spa_ruleset.id
  order                     = 1
  conditions {
    url_file_extension_condition {
      operator     = "LessThan"
      match_values = ["1"]
    }
  }

  actions {
    url_rewrite_action {
      source_pattern = "/"
      destination    = "/index.html"
    }
  }
}
