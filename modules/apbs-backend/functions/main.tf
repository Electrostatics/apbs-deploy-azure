locals {
  normalized_name = replace(lower(var.name), "-", "")
}

resource "azurerm_storage_account" "funcstorage" {
  name                = "${local.normalized_name}storage"
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    Name = var.name
  }
}

resource "azurerm_storage_container" "funccontainer" {
  name                  = "${local.normalized_name}-container"
  storage_account_id    = azurerm_storage_account.funcstorage.id
  container_access_type = "private"
}


resource "azurerm_service_plan" "funcserviceplan" {
  name                = "${local.normalized_name}-service-plan"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "funcapp" {
  name                       = "${local.normalized_name}-function-app"
  location                   = var.resource_group_location
  resource_group_name        = var.resource_group_name
  storage_account_name       = azurerm_storage_account.funcstorage.name
  storage_account_access_key = azurerm_storage_account.funcstorage.primary_access_key
  service_plan_id            = azurerm_service_plan.funcserviceplan.id
  site_config {}
}
