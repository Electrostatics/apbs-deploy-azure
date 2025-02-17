data "azurerm_container_registry" "acr" {
  name                = var.registry_name
  resource_group_name = var.registry_resource_group_name
}

resource "azurerm_user_assigned_identity" "container_app_identity" {
  name                = "${var.app_name}-identity"
  location            = var.location
  resource_group_name = var.backend_resource_group_name
}

resource "azurerm_role_assignment" "container_app_role_assignment" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.container_app_identity.principal_id
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "container_app_log_analytics" {
  name                = "${var.app_name}-log-analytics"
  location            = var.location
  resource_group_name = var.backend_resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "app_env" {
  name                       = "${var.app_name}-env"
  location                   = var.location
  resource_group_name        = var.backend_resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.container_app_log_analytics.id
}

resource "azurerm_container_app_job" "app" {
  name                         = var.app_name
  resource_group_name          = var.backend_resource_group_name
  location                     = var.location
  container_app_environment_id = azurerm_container_app_environment.app_env.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_app_identity.id]
  }

  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.container_app_identity.id
  }

  replica_timeout_in_seconds = var.replica_timeout_in_seconds
  replica_retry_limit        = 1

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "apbscontainer"
      image  = "${data.azurerm_container_registry.acr.login_server}/${var.image_name}:${var.image_tag}"
      cpu    = var.cpu
      memory = var.memory
      env {
        name  = "APBS_QUEUE_NAME"
        value = var.job_queue_name
      }
      env {
        # Swap this to a role instead
        name  = "APBS_QUEUE_CONNECTION_STRING"
        value = var.storage_primary_connection_string
      }
    }
  }
}
