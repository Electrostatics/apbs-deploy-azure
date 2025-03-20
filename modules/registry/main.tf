resource "azurerm_container_registry" "registry" {
  name                = var.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_container_registry_task" "cleanup" {
  name                  = "cleanup"
  container_registry_id = azurerm_container_registry.registry.id
  platform {
    os = "Linux"
  }
  encoded_step {
    task_content = yamlencode({
      version = "v1.1.0"
      steps = [
        {
          cmd                             = "acr purge --filter '${var.container_name}:${var.container_tag_regex}' --untagged --ago 0d --keep 5"
          disableWorkingDirectoryOverride = true
          timeout                         = 3600
        }
      ]
    })
    context_path = "/dev/null"
  }

  timer_trigger {
    name     = "cleanup_timer"
    schedule = var.cleanup_schedule
    enabled  = true
  }
}
