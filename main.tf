# =============================================================================
# Azure Infrastructure - Caddy Cluster with DDoS Protection, WAF, Rate Limiting
# =============================================================================
# Architecture:
# Client → (DDoS) → Standard LB → Caddy (TLS+WAF+RateLimit) → Upstream
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # 使用本地存储
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Random suffix for globally unique names
# -----------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# -----------------------------------------------------------------------------
# Modules
# -----------------------------------------------------------------------------

# Network Module - VNet, Subnet, NSG, DDoS Protection, Public IP
module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  vnet_address_space    = var.vnet_address_space
  subnet_address_prefix = var.subnet_address_prefix
  enable_ddos_protection = var.enable_ddos_protection

  tags = var.tags
}

# Storage Module - Storage Account + Azure Files
module "storage" {
  source = "./modules/storage"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  subnet_id                  = module.network.subnet_id
  vnet_id                    = module.network.vnet_id
  storage_account_tier       = var.storage_account_tier
  storage_replication_type   = var.storage_replication_type
  file_share_quota_gb        = var.file_share_quota_gb

  tags = var.tags
}

# Key Vault Module
module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  subnet_id                    = module.network.subnet_id
  vnet_id                      = module.network.vnet_id
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  admin_object_id              = data.azurerm_client_config.current.object_id
  cloudflare_api_token         = var.cloudflare_api_token
  upstream_credentials         = var.upstream_credentials

  tags = var.tags
}

# Load Balancer Module
module "loadbalancer" {
  source = "./modules/loadbalancer"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  public_ip_id = module.network.public_ip_id

  tags = var.tags
}

# Redis Module - For distributed rate limiting
module "redis" {
  source = "./modules/redis"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  subnet_id    = module.network.subnet_id
  vnet_id      = module.network.vnet_id
  keyvault_id  = module.keyvault.keyvault_id

  redis_sku      = var.redis_sku
  redis_family   = var.redis_family
  redis_capacity = var.redis_capacity

  tags = var.tags

  depends_on = [module.keyvault]
}

# VMSS Module - Caddy Cluster
module "vmss" {
  source = "./modules/vmss"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  suffix              = random_string.suffix.result

  subnet_id                     = module.network.subnet_id
  lb_backend_pool_id            = module.loadbalancer.backend_pool_id
  storage_account_name          = module.storage.storage_account_name
  storage_account_key           = module.storage.storage_account_primary_key
  file_share_name               = module.storage.file_share_name
  keyvault_id                   = module.keyvault.keyvault_id

  vmss_sku                      = var.vmss_sku
  vmss_instance_count           = var.vmss_instance_count
  admin_username                = var.admin_username
  admin_ssh_public_key          = var.admin_ssh_public_key

  upstream_servers              = var.upstream_servers
  domain_name                   = var.domain_name
  acme_email                    = var.acme_email
  cloudflare_api_token_secret_id = module.keyvault.cloudflare_api_token_secret_id

  # Redis for distributed rate limiting
  redis_host                    = module.redis.redis_hostname
  redis_port                    = 6380  # Azure Redis uses 6380 for TLS
  redis_password                = module.redis.redis_primary_access_key
  
  # Rate limit storage backend selection
  rate_limit_storage_backend    = var.rate_limit_storage_backend

  tags = var.tags

  depends_on = [
    module.loadbalancer,
    module.storage,
    module.keyvault,
    module.redis
  ]
}
