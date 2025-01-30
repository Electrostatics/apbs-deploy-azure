resource "azurerm_storage_account" "storage" {
  name                = replace(lower(var.name), "-", "")
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    Name = var.name
  }

  blob_properties {
    last_access_time_enabled = var.enable_last_access_time
    cors_rule {
      allowed_headers    = ["content-type", "accept", "x-ms-*", "authorization", "origin"]
      allowed_methods    = ["PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["x-ms-*"]
      max_age_in_seconds = 3600
    }
  }
}
