output "storage_account" {
  value = {
    name               = azurerm_storage_account.funcstorage.name
    primary_access_key = azurerm_storage_account.funcstorage.primary_access_key
  }
}
