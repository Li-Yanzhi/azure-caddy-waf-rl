# =============================================================================
# Redis Module - Azure Cache for Redis
# =============================================================================
# Used for distributed rate limiting across Caddy VMSS instances
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Random password for Redis
# -----------------------------------------------------------------------------
resource "random_password" "redis" {
  length           = 32
  special          = true
  override_special = "!@#$%"
}

# -----------------------------------------------------------------------------
# Azure Cache for Redis
# -----------------------------------------------------------------------------
resource "azurerm_redis_cache" "main" {
  name                = "redis-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku
  
  # Security settings
  minimum_tls_version   = "1.2"
  enable_non_ssl_port   = false
  public_network_access_enabled = false

  redis_configuration {
    maxmemory_policy   = "volatile-lru"
    maxmemory_reserved = 50
  }

  # Patch schedule (maintenance window)
  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 2
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Private Endpoint for Redis
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_redis_cache.main.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Redis
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "vnet-link-redis"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_a_record" "redis" {
  name                = azurerm_redis_cache.main.name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address]
}

# -----------------------------------------------------------------------------
# Store Redis password in Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "redis_password" {
  count = var.store_password_in_keyvault ? 1 : 0

  name         = "redis-password"
  value        = azurerm_redis_cache.main.primary_access_key
  key_vault_id = var.keyvault_id
}
