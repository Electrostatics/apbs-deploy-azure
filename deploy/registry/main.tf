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
    storage_account_name = "apbsterraformdeploy"
    container_name       = "tfstate"
    key                  = "registry.tfstate"
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
  registry_name = "apbsregistry${random_id.apbs-registry.hex}"
}

data "azurerm_client_config" "current" {}


resource "azurerm_resource_group" "apbs-registry" {
  name     = "apbs-registry"
  location = "East US"
}

resource "random_id" "apbs-registry" {
  keepers = {
    resource_group_name = azurerm_resource_group.apbs-registry.name
  }
  byte_length = 4
}

module "registry" {
  source              = "../../modules/registry"
  location            = azurerm_resource_group.apbs-registry.location
  registry_name       = local.registry_name
  resource_group_name = azurerm_resource_group.apbs-registry.name
  container_name      = "apbs-azure"
}

resource "github_actions_secret" "acr_url" {
  repository      = "apbs-deploy-azure"
  secret_name     = "ACR_URL"
  plaintext_value = module.registry.registry.login_server
}

resource "github_actions_secret" "acr_name" {
  repository      = "apbs-deploy-azure"
  secret_name     = "ACR_NAME"
  plaintext_value = local.registry_name
}

resource "github_actions_secret" "acr_resource_group_name" {
  repository      = "apbs-deploy-azure"
  secret_name     = "ACR_RESOURCE_GROUP_NAME"
  plaintext_value = azurerm_resource_group.apbs-registry.name
}
