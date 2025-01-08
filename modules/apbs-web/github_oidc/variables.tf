variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "resource_group_location" {
  description = "Resource group location"
  type        = string
}

variable "github_info" {
  description = "GitHub repository and branch information"
  type = object({
    branch        = string
    repository    = string
    secret_prefix = string
  })
}

# variable "branch" {
#   description = "Branch to use for OIDC"
#   type        = string
#   default     = "main"
# }

# variable "repository" {
#   description = "GitHub repository name"
#   type        = string
# }
