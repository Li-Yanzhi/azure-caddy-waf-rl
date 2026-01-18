# =============================================================================
# Key Vault Module - Variables
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

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "admin_object_id" {
  description = "Object ID of the admin user/service principal"
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

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS-01 challenge"
  type        = string
  sensitive   = true
  default     = ""
}

variable "upstream_credentials" {
  description = "Credentials for upstream services"
  type        = string
  sensitive   = true
  default     = "{}"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
