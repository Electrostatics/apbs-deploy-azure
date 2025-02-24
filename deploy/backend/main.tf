terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.14.0"
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
  github_info = {
    repository    = "apbs-web-testing-fork"
    branch        = "aws-release"
    secret_prefix = "AZURE"
  }
  blobs = ["inputs", "outputs"]
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
  name     = "apbs-backend"
  location = "East US"
}

module "backend_storage" {
  source                  = "../../modules/apbs-backend/storage-account"
  name                    = "apbs-blobs"
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
  repository      = local.github_info.repository
  secret_name     = "${local.github_info.secret_prefix}_OUTPUT_BLOB_STORAGE_URL"
  plaintext_value = "https://${module.backend_storage.storage_account.name}.blob.core.windows.net/${module.outputs_blob.name}"
}


resource "azurerm_storage_management_policy" "inputs" {
  storage_account_id = module.backend_storage.storage_account.id

  rule {
    name    = "inputs"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["inputs/"]
    }
    actions {
      base_blob {
        # Put this into "cool" after 14 days
        tier_to_cool_after_days_since_last_access_time_greater_than = 14
        # Put this into "archive" after 30 days
        tier_to_archive_after_days_since_last_access_time_greater_than = 30
        # Delete after 60 days
        delete_after_days_since_last_access_time_greater_than = 60
      }
    }
  }
}

resource "azurerm_storage_queue" "apbs-backend-queue" {
  name                 = "apbsbackendqueue"
  storage_account_name = module.backend_storage.storage_account.name
}

resource "azurerm_user_assigned_identity" "apbs-backend-queue-access" {
  name                = "apbs-backend-queue-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_definition" "apbs-backend-queue-restrictions" {
  name = "APBS Backend Queue Access"
  # Restrict this to the queue
  scope = azurerm_storage_queue.apbs-backend-queue.resource_manager_id
  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/queueServices/queues/read",
      "Microsoft.Storage/storageAccounts/queueServices/queues/write",
      "Microsoft.Storage/storageAccounts/queueServices/queues/delete",
      "Microsoft.Storage/storageAccounts/listKeys/action"
    ]
    not_actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/read",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/write",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/delete",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/process/action"
    ]
    not_data_actions = []
  }
}

resource "azurerm_role_assignment" "apbs-backend-queue-access" {
  scope              = azurerm_storage_queue.apbs-backend-queue.resource_manager_id
  role_definition_id = azurerm_role_definition.apbs-backend-queue-restrictions.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.apbs-backend-queue-access.principal_id
}

resource "azurerm_user_assigned_identity" "apbs-output-blob-access" {
  name                = "apbs-output-blob-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_assignment" "apbs-output-blob-access" {
  scope                = module.outputs_blob.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.apbs-output-blob-access.principal_id
}


resource "azurerm_user_assigned_identity" "apbs-input-blob-access" {
  name                = "apbs-input-blob-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_assignment" "apbs-input-blob-access" {
  scope                = module.inputs_blob.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.apbs-input-blob-access.principal_id
}



module "container-app" {
  source                            = "../../modules/apbs-backend/container-app"
  app_name                          = "apbs-app"
  location                          = azurerm_resource_group.apbs-backend.location
  backend_resource_group_name       = azurerm_resource_group.apbs-backend.name
  cpu                               = 4.0
  memory                            = "8Gi"
  image_name                        = "apbs-azure"
  image_tag                         = "latest"
  registry_name                     = var.acr_name
  registry_resource_group_name      = var.acr_resource_group_name
  job_queue_name                    = resource.azurerm_storage_queue.apbs-backend-queue.name
  storage_primary_connection_string = module.backend_storage.storage_account.primary_connection_string
  job_queue_url                     = module.backend_storage.storage_account.primary_queue_endpoint
  storage_account_url               = module.backend_storage.storage_account.primary_blob_endpoint
  extra_role_ids = [
    azurerm_role_assignment.apbs-backend-queue-access.id,
    azurerm_role_assignment.apbs-input-blob-access.id,
    azurerm_role_assignment.apbs-output-blob-access.id
  ]
}

resource "azurerm_user_assigned_identity" "apbs-container-app-access" {
  name                = "apbs-container-app-access"
  location            = azurerm_resource_group.apbs-backend.location
  resource_group_name = azurerm_resource_group.apbs-backend.name
}

resource "azurerm_role_assignment" "apbs-container-app-access" {
  scope                = module.container-app.id
  role_definition_name = "Container Apps Jobs Operator"
  principal_id         = azurerm_user_assigned_identity.apbs-container-app-access.principal_id
}
