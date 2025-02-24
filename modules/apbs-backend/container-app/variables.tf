variable "registry_name" {
  description = "The name of the container registry"
  type        = string
}

variable "registry_resource_group_name" {
  description = "The name of the resource group containing the container registry"
  type        = string
}

variable "app_name" {
  description = "The name of the container app"
  type        = string
}

variable "location" {
  description = "The location of the container app"
  type        = string
}

variable "backend_resource_group_name" {
  description = "The name of the resource group containing the container app"
  type        = string
}

variable "replica_timeout_in_seconds" {
  description = "The timeout in seconds for the container app"
  type        = number
  default     = 600
}

variable "cpu" {
  description = "The CPU for the container app"
  type        = number
}

variable "memory" {
  description = "The memory for the container app"
  type        = string
}

variable "image_name" {
  description = "The name of the container image"
  type        = string
}

variable "image_tag" {
  description = "The tag of the container image"
  type        = string
}

variable "job_queue_name" {
  description = "The job queue"
  type        = string
  sensitive   = true
}

variable "storage_primary_connection_string" {
  description = "The primary connection string for the storage account"
  type        = string
  sensitive   = true
}

variable "execution_role_id" {
  description = "The execution role to use"
  type        = string
}

variable "storage_account_url" {
  description = "The URL of the storage account"
  type        = string
}

variable "job_queue_url" {
  description = "The URL of the queue"
  type        = string
}
