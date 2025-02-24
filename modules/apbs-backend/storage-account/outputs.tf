output "storage_account" {
  value = {
    name                      = azurerm_storage_account.storage.name
    primary_access_key        = azurerm_storage_account.storage.primary_access_key
    id                        = azurerm_storage_account.storage.id
    primary_connection_string = azurerm_storage_account.storage.primary_connection_string
    primary_queue_endpoint    = azurerm_storage_account.storage.primary_queue_endpoint
    primary_blob_endpoint     = azurerm_storage_account.storage.primary_blob_endpoint
  }
  sensitive = true
}
