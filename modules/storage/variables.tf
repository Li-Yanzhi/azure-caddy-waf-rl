# =============================================================================
# Storage Module - Variables
# =============================================================================

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "suffix" {
  description = "Unique suffix for resource names"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for service endpoints"
  type        = string
}

variable "vnet_id" {
  description = "ID of the VNet for private DNS link"
  type        = string
}

variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage replication type (LRS, ZRS, GRS, etc.)"
  type        = string
  default     = "ZRS"
}

variable "file_share_quota_gb" {
  description = "Quota for the file share in GB"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
