output "github_oidc_principal_id" {
  value       = azurerm_user_assigned_identity.github_oidc_identity.principal_id
  description = "The principal ID of the OIDC user"
}
