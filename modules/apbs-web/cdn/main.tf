locals {
  repository = split("/", var.repository)[1]
  base_secrets = {
    "CDN_PROFILE_NAME" = azurerm_cdn_profile.static_site_cdn_profile.name
    "CDN_ENDPOINT"     = azurerm_cdn_endpoint.static_site_endpoint.name
  }
  secrets = {
    for key, value in local.base_secrets : "${var.gh_secret_prefix}_${key}" => value
  }
}

resource "azurerm_cdn_profile" "static_site_cdn_profile" {
  name                = "static-site-cdn-profile"
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location
  sku                 = "Standard_Microsoft"
}


# CDN Endpoint
resource "azurerm_cdn_endpoint" "static_site_endpoint" {
  name                = "static-site-endpoint"
  profile_name        = azurerm_cdn_profile.static_site_cdn_profile.name
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name

  origin {
    name      = "static-site-origin"
    host_name = var.primary_web_host
  }

  optimization_type = "GeneralWebDelivery"

  delivery_rule {
    name  = "EnforceHTTPS"
    order = 1

    request_scheme_condition {
      match_values = ["HTTP"]
      operator     = "Equal"
    }

    url_redirect_action {
      redirect_type = "Moved"
      protocol      = "Https"
    }
  }
}

resource "azurerm_role_assignment" "cdn_role_assignment" {
  principal_id         = var.principal_id
  role_definition_name = "CDN Endpoint Contributor"
  scope                = azurerm_cdn_profile.static_site_cdn_profile.id
}

resource "github_actions_secret" "secrets" {
  for_each        = local.secrets
  repository      = local.repository
  secret_name     = each.key
  plaintext_value = each.value
}
