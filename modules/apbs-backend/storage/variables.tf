variable "storage_account_id" {
  description = "ID of the storage account"
  type        = string
}

variable "blob_name" {
  description = "The name of the blob to create"
  type        = string
}

variable "is_public" {
  description = "Whether the blob should be public"
  type        = bool
  default     = false
}
