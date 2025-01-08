output "storage_account_id" {
  description = "The id of the storage account"
  value       = azurerm_storage_account.storage.id
}

output "primary_web_host" {
  description = "The primary web host"
  value       = azurerm_storage_account.storage.primary_web_host
}

# output "oidc_principal_id" {
#   description = "The principle ID of the user to use in CI"
#   value       = azurerm_user_assigned_identity.github_oidc_identity.principal_id
# }
