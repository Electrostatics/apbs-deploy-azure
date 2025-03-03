variable "name" {
  description = "Name of the storage account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "resource_group_location" {
  description = "Resource group location"
  type        = string
}

variable "plan_name" {
  description = "Name of the function app plan"
  type        = string
}
