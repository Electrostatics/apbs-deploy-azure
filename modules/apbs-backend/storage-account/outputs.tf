output "storage_account" {
  value = {
    name               = azurerm_storage_account.storage.name
    primary_access_key = azurerm_storage_account.storage.primary_access_key
    id                 = azurerm_storage_account.storage.id
  }
}
