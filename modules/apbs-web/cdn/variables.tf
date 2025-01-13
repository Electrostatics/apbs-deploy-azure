variable "primary_web_host" {
  type        = string
  description = "The primary web host"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "resource_group_location" {
  description = "Resource group location"
  type        = string
}

variable "repository" {
  description = "The repository to deploy"
  type        = string
}

variable "principal_id" {
  description = "The principle ID of the user to use in CI"
  type        = string
}

variable "gh_secret_prefix" {
  description = "The prefix to use for GitHub secrets"
  type        = string
  default     = "AZURE"
}

variable "name" {
  description = "The name of the Azure FrontDoor Profile"
  type        = string
  default     = "static-site-cdn-profile"
}

variable "sku" {
  description = "The SKU of the Azure FrontDoor Profile"
  type        = string
  default     = "Standard_AzureFrontDoor"
}
