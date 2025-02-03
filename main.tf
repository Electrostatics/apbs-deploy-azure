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
  token = var.github_token
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
    repository    = "omsf-eco-infra/apbs-web-testing-fork"
    branch        = "aws-release"
    secret_prefix = "AZURE"
  }
  blobs = ["inputs", "outputs"]
}


resource "azurerm_resource_group" "github" {
  name     = "github"
  location = "East US"
}

module "github_oidc" {
  source                  = "./modules/apbs-web/github_oidc"
  resource_group_name     = azurerm_resource_group.github.name
  resource_group_location = azurerm_resource_group.github.location
  github_info             = local.github_info
}

# Module to create the static site in Azure
module "static_site" {
  source                   = "./modules/apbs-web/static_site"
  name                     = "apbs-web-testing-deploy"
  resource_group_location  = azurerm_resource_group.github.location
  resource_group_name      = azurerm_resource_group.github.name
  github_oidc_principal_id = module.github_oidc.github_oidc_principal_id
  repository               = local.github_info.repository
  gh_secret_prefix         = local.github_info.secret_prefix
}

module "cdn" {
  source                  = "./modules/apbs-web/cdn"
  name                    = "apbs"
  primary_web_host        = module.static_site.primary_web_host
  resource_group_name     = azurerm_resource_group.github.name
  resource_group_location = azurerm_resource_group.github.location
  repository              = local.github_info.repository
  principal_id            = module.github_oidc.github_oidc_principal_id
}

module "backend_storage" {
  source                  = "./modules/apbs-backend/storage-account"
  name                    = "apbs-blobs"
  resource_group_name     = azurerm_resource_group.github.name
  resource_group_location = azurerm_resource_group.github.location
}

module "inputs_blob" {
  source             = "./modules/apbs-backend/storage"
  blob_name          = "inputs"
  storage_account_id = module.backend_storage.storage_account.id
}

module "outputs_blob" {
  source             = "./modules/apbs-backend/storage"
  blob_name          = "outputs"
  storage_account_id = module.backend_storage.storage_account.id
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


# module "blobs" {
#   source                  = "./modules/apbs-backend/storage"
#   blobs                   = ["inputs", "outputs"]
#   name                    = "apbs-blobs"
#   resource_group_name     = azurerm_resource_group.github.name
#   resource_group_location = azurerm_resource_group.github.location
# }

# module "functions" {
#   source                  = "./modules/apbs-backend/functions"
#   name                    = "apbs-ingest"
#   resource_group_name     = azurerm_resource_group.github.name
#   resource_group_location = azurerm_resource_group.github.location
#   resource_group_id       = azurerm_resource_group.github.id
#   plan_name               = "ingest-plan"
# }
