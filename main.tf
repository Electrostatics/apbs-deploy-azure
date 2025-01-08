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
  features {}
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

# TODO: Need to move off of the free trial acount for to test this
# module "cdn" {
#   source                  = "./modules/apbs-web/cdn"
#   primary_web_host        = module.bucket_and_role.primary_web_host
#   resource_group_name     = azurerm_resource_group.github.name
#   resource_group_location = azurerm_resource_group.github.location
#   repository              = "omsf-eco-infra/apbs-web-testing-fork"
#   principal_id            = module.bucket_and_role.oidc_principal_id
# }

# output "cdn_endpoint" {
#   value = module.cdn.cdn_endpoint_url
# }
