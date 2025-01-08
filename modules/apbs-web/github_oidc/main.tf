locals {
  repository = split("/", var.github_info.repository)[1]
  base_secrets = {
    "SUBSCRIPTION_ID" = data.azurerm_client_config.current.subscription_id
    "TENANT_ID"       = data.azurerm_client_config.current.tenant_id
    "CLIENT_ID"       = azurerm_user_assigned_identity.github_oidc_identity.client_id
  }
  secrets = {
    for key, value in local.base_secrets : "${var.github_info.secret_prefix}_${key}" => value
  }
}

resource "azurerm_user_assigned_identity" "github_oidc_identity" {
  name                = "github-oidc-identity"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name
}

resource "azurerm_federated_identity_credential" "github_oidc_credential" {
  # Change me to be a bit more dynamic
  name                = "github-oidc-credential"
  parent_id           = azurerm_user_assigned_identity.github_oidc_identity.id
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_info.repository}:ref:refs/heads/${var.github_info.branch}"
}

resource "github_actions_secret" "secrets" {
  for_each        = local.secrets
  repository      = local.repository
  secret_name     = each.key
  plaintext_value = each.value
}
