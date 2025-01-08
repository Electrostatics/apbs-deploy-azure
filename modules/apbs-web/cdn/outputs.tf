output "cdn_endpoint_url" {
  value = "https://${azurerm_cdn_endpoint.static_site_endpoint.fqdn}"
}
