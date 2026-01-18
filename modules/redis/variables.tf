# =============================================================================
# Redis Module - Variables
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
  description = "ID of the subnet for private endpoint"
  type        = string
}

variable "vnet_id" {
  description = "ID of the VNet for private DNS link"
  type        = string
}

variable "keyvault_id" {
  description = "ID of the Key Vault to store Redis password"
  type        = string
  default     = null
}

variable "store_password_in_keyvault" {
  description = "Whether to store Redis password in Key Vault"
  type        = bool
  default     = false
}

variable "redis_capacity" {
  description = "Redis cache capacity (0-6 for Basic/Standard, 1-5 for Premium)"
  type        = number
  default     = 0
}

variable "redis_family" {
  description = "Redis cache family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "redis_sku" {
  description = "Redis cache SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
