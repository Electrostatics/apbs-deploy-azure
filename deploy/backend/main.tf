terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tf"
    storage_account_name = "apbsterraform"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "github" {
  owner = "omsf-eco-infra"
}

provider "azurerm" {
  features {
    resource_group {
      # This allows us to delete an entire resource group
      # even if it contains resources not managed by terraform.
      # This will be removed in the future.
      prevent_deletion_if_contains_resources = false
    }
  }
  # This makes it such that we don't have to have
  # wait to have all of the resources enabled on the subscription
  resource_provider_registrations = "none"
}


locals {
  # Workspace specific config
  workspace_config = {
    default = {
      resource_group_name          = "apbs-backend"
      app_name                     = "apbs-app"
      storage_account_name         = "apbsblobs"
      backend_role_definition_name = "APBS Backend Data Access"
      cpu                          = 4.0
      memory                       = "8Gi"
      image_tag                    = "latest"
      replica_timeout_in_seconds   = 1800
      github_info = {
        repository    = "apbs-web-testing-fork"
        branch        = "aws-release"
        secret_prefix = "AZURE"
      }
      storage_policy = {
        inputs = {
          cool_after    = 14
          archive_after = 30
          delete_after  = 60
        }
        outputs = {
          cool_after    = 14
          archive_after = 30
          delete_after  = 60
        }
      }
    }
    dev = {
      resource_group_name          = "apbs-backend-dev"
      app_name                     = "apbs-app-dev"
      storage_account_name         = "apbsblobsdev"
      backend_role_definition_name = "APBS Backend Data Access Dev"
      cpu                          = 2.0
      memory                       = "4Gi"
      image_tag                    = "latest"
      replica_timeout_in_seconds   = 600
      github_info = {
        repository    = "apbs-web-testing-fork"
        branch        = "aws-release"
        secret_prefix = "AZURE_DEV"
      }
      storage_policy = {
        inputs = {
          cool_after    = null
          archive_after = null
          delete_after  = 7
        }
        outputs = {
          cool_after    = null
          archive_after = null
          delete_after  = 7
        }
      }
    }
  }
  env_config = lookup(local.workspace_config, terraform.workspace, local.workspace_config.dev)
  blobs      = ["inputs", "outputs"]
}

variable "acr_name" {
  description = "The Azure Container Registry name"
  type        = string
  sensitive   = true
}

variable "acr_resource_group_name" {
  description = "The name of the resource group containing the Azure Container Registry"
  type        = string
  sensitive   = true
}

data "azurerm_client_config" "current" {}


resource "azurerm_resource_group" "apbs-backend" {
  name     = local.env_config.resource_group_name
  location = "East US"
}

module "backend_storage" {
  source                  = "../../modules/apbs-backend/storage-account"
  name                    = local.env_config.storage_account_name
  resource_group_name     = azurerm_resource_group.apbs-backend.name
  resource_group_location = azurerm_resource_group.apbs-backend.location
}

module "inputs_blob" {
  source             = "../../modules/apbs-backend/storage"
  blob_name          = "inputs"
  storage_account_id = module.backend_storage.storage_account.id
}

module "outputs_blob" {
  source             = "../../modules/apbs-backend/storage"
  blob_name          = "outputs"
  storage_account_id = module.backend_storage.storage_account.id
  is_public          = true
}

resource "github_actions_secret" "output_blob_storage_url" {
  repository      = local.env_config.github_info.repository
  secret_name     = "${local.env_config.github_info.secret_prefix}_OUTPUT_BLOB_STORAGE_URL"
  plaintext_value = "https://${module.backend_storage.storage_account.name}.blob.core.windows.net/${module.outputs_blob.name}"
}


resource "azurerm_storage_management_policy" "storage_policies" {
  storage_account_id = module.backend_storage.storage_account.id
  dynamic "rule" {
    for_each = local.env_config.storage_policy
    content {
      name    = "${rule.key}-lifecycle"
      enabled = true
      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }
      actions {
        base_blob {
          tier_to_cool_after_days_since_last_access_time_greater_than    = rule.value.cool_after
          tier_to_archive_after_days_since_last_access_time_greater_than = rule.value.archive_after
          delete_after_days_since_last_access_time_greater_than          = rule.value.delete_after
        }
      }
    }
  }

}

resource "azurerm_storage_queue" "apbs-backend-queue" {
  name                 = "apbsbackendqueue"
  storage_account_name = module.backend_storage.storage_account.name
}


# The following is the identity used by the container app to access the storage account,
# the queue, and the blob storage.
resource "azurerm_user_assigned_identity" "apbs-backend-data-access" {
  name                = "apbs-backend-data-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_assignment" "apbs-backend-data-access" {
  scope                = module.backend_storage.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = sensitive(azurerm_user_assigned_identity.apbs-backend-data-access.principal_id)
}

resource "azurerm_role_assignment" "apbs-backend-queue-access" {
  scope                = module.backend_storage.storage_account.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = sensitive(azurerm_user_assigned_identity.apbs-backend-data-access.principal_id)
}


module "container-app" {
  source                       = "../../modules/apbs-backend/container-app"
  app_name                     = "apbs-app"
  location                     = azurerm_resource_group.apbs-backend.location
  backend_resource_group_name  = azurerm_resource_group.apbs-backend.name
  cpu                          = local.env_config.cpu
  memory                       = local.env_config.memory
  image_name                   = "apbs-azure"
  image_tag                    = local.env_config.image_tag
  registry_name                = var.acr_name
  registry_resource_group_name = var.acr_resource_group_name
  job_queue_name               = resource.azurerm_storage_queue.apbs-backend-queue.name
  job_queue_url                = module.backend_storage.storage_account.primary_queue_endpoint
  storage_account_url          = module.backend_storage.storage_account.primary_blob_endpoint
  execution_role_id            = sensitive(azurerm_user_assigned_identity.apbs-backend-data-access.id)
  execution_role_client_id     = sensitive(azurerm_user_assigned_identity.apbs-backend-data-access.client_id)
  replica_timeout_in_seconds   = local.env_config.replica_timeout_in_seconds
}

# These are currently being used by the static web app but we are not managing
# that with terraform at this time.
resource "azurerm_user_assigned_identity" "apbs-container-app-access" {
  name                = "apbs-container-app-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_assignment" "apbs-container-app-access" {
  scope                = module.container-app.id
  role_definition_name = "Container Apps Jobs Operator"
  principal_id         = sensitive(azurerm_user_assigned_identity.apbs-container-app-access.principal_id)
}

