variable "resource_group_name" {
  description = "The name of the resource group in which to create the resources."
  type        = string
}

variable "location" {
  description = "The location/region where the resources will be created."
  type        = string
}

variable "registry_name" {
  description = "The name of the container registry."
  type        = string
}

variable "container_name" {
  description = "The name of the container to be cleaned up."
  type        = string
}

variable "container_tag_regex" {
  description = "The regex to match the container tags to be cleaned up."
  type        = string
  default     = ".*"
}

variable "cleanup_schedule" {
  description = "The schedule for the cleanup task."
  type        = string
  default     = "0 0 * * 0"
}
