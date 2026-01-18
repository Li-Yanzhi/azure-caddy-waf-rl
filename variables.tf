# =============================================================================
# Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General Settings
# -----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-caddy-cluster"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastasia"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "caddy-cluster"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Network Settings
# -----------------------------------------------------------------------------
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the Caddy subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "enable_ddos_protection" {
  description = "Enable Azure DDoS Protection Standard (additional cost ~$2,944/month)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Storage Settings
# -----------------------------------------------------------------------------
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage replication type"
  type        = string
  default     = "ZRS"
}

variable "file_share_quota_gb" {
  description = "Quota for the Azure Files share in GB"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Redis Settings
# -----------------------------------------------------------------------------
variable "redis_sku" {
  description = "Redis cache SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "redis_family" {
  description = "Redis cache family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis cache capacity (0-6 for Basic/Standard, 1-5 for Premium)"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# Rate Limiting Settings
# -----------------------------------------------------------------------------
variable "rate_limit_storage_backend" {
  description = "Storage backend for rate limiting state: 'azure_files' or 'redis'. Redis provides lower latency for state sync."
  type        = string
  default     = "azure_files"

  validation {
    condition     = contains(["azure_files", "redis"], var.rate_limit_storage_backend)
    error_message = "rate_limit_storage_backend must be either 'azure_files' or 'redis'."
  }
}

# -----------------------------------------------------------------------------
# VMSS Settings
# -----------------------------------------------------------------------------
variable "vmss_sku" {
  description = "SKU for VMSS instances"
  type        = string
  default     = "Standard_B2s"
}

variable "vmss_instance_count" {
  description = "Number of VMSS instances"
  type        = number
  default     = 2
}

variable "admin_username" {
  description = "Admin username for VMSS instances"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VMSS admin access"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Caddy/Application Settings
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Domain name for the application (e.g., example.com)"
  type        = string
}

variable "acme_email" {
  description = "Email for ACME certificate registration"
  type        = string
}

variable "upstream_servers" {
  description = "List of upstream server addresses (e.g., ['10.0.2.10:8080', '10.0.2.11:8080'])"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS-01 challenge"
  type        = string
  sensitive   = true
  default     = ""
}

variable "upstream_credentials" {
  description = "Credentials for upstream services (JSON format)"
  type        = string
  sensitive   = true
  default     = "{}"
}
