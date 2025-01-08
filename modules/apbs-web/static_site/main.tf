locals {
  repository = split("/", var.repository)[1]
  base_secrets = {
    "STORAGE_ACCOUNT" = azurerm_storage_account.storage.name
  }
  secrets = {
    for key, value in local.base_secrets : "${var.gh_secret_prefix}_${key}" => value
  }
}

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
}

resource "azurerm_storage_account_static_website" "website" {
  storage_account_id = azurerm_storage_account.storage.id
  index_document     = "index.html"
}

resource "azurerm_role_assignment" "github_oidc_role_assignment" {
  principal_id         = var.github_oidc_principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.storage.id
}

resource "azurerm_role_assignment" "github_oidc_reader" {
  principal_id         = var.github_oidc_principal_id
  role_definition_name = "Reader"
  scope                = azurerm_storage_account.storage.id
}

resource "github_actions_secret" "secrets" {
  for_each        = local.secrets
  repository      = local.repository
  secret_name     = each.key
  plaintext_value = each.value
}
