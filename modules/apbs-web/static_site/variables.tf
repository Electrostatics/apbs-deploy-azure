variable "name" {
  description = "Name of the Storage Account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "resource_group_location" {
  description = "Resource group location"
  type        = string
}

variable "branch" {
  description = "Branch to use for OIDC"
  type        = string
  default     = "main"
}

variable "github_oidc_principal_id" {
  description = "GitHub OIDC"
  type        = string
}

variable "repository" {
  description = "GitHub repository name"
  type        = string
}

variable "gh_secret_prefix" {
  description = "Prefix to use for name of secrets in GitHub Actions"
  type        = string
  default     = "AZURE"
}
