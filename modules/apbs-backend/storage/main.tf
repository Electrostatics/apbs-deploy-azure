resource "azurerm_storage_container" "blob" {
  name                  = var.blob_name
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
}
