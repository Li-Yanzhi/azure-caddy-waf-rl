# =============================================================================
# VMSS Module - Variables
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
  description = "ID of the subnet for VMSS"
  type        = string
}

variable "lb_backend_pool_id" {
  description = "ID of the Load Balancer backend pool"
  type        = string
}

variable "keyvault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the Storage Account for Azure Files"
  type        = string
}

variable "storage_account_key" {
  description = "Access key for the Storage Account"
  type        = string
  sensitive   = true
}

variable "file_share_name" {
  description = "Name of the Azure Files share"
  type        = string
}

variable "vmss_sku" {
  description = "SKU for VMSS instances"
  type        = string
  default     = "Standard_B2s"
}

variable "vmss_instance_count" {
  description = "Initial number of VMSS instances"
  type        = number
  default     = 2
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for admin access"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Caddy"
  type        = string
}

variable "acme_email" {
  description = "Email for ACME certificate registration"
  type        = string
}

variable "upstream_servers" {
  description = "List of upstream server addresses"
  type        = list(string)
}

variable "cloudflare_api_token_secret_id" {
  description = "Key Vault secret ID for Cloudflare API token"
  type        = string
  default     = null
}

variable "redis_host" {
  description = "Redis hostname for distributed rate limiting"
  type        = string
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

variable "redis_port" {
  description = "Redis port (usually 6380 for Azure Redis with TLS)"
  type        = number
  default     = 6380
}

variable "rate_limit_storage_backend" {
  description = "Storage backend for rate limiting: 'azure_files' or 'redis'"
  type        = string
  default     = "azure_files"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
