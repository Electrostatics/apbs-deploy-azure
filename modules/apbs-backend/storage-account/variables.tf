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

variable "enable_last_access_time" {
  description = "Enable last access time tracking for the storage account"
  type        = bool
  default     = true
}
