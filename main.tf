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

output "cdn_host_name" {
  value = module.cdn.cdn_host_name
}
