# =============================================================================
# Key Vault Module - Secrets Management
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
  }
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                = "kv-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Security settings
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enabled_for_disk_encryption     = false
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7

  # Network ACLs - restrict to VNet
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.subnet_id]
    ip_rules                   = []
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Access Policy for Terraform Admin
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_access_policy" "admin" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = var.admin_object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover"
  ]

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Purge"
  ]
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "cloudflare_api_token" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  name         = "cloudflare-api-token"
  value        = var.cloudflare_api_token
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.admin]
}

resource "azurerm_key_vault_secret" "upstream_credentials" {
  count = var.upstream_credentials != "{}" ? 1 : 0

  name         = "upstream-credentials"
  value        = var.upstream_credentials
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.admin]
}

# -----------------------------------------------------------------------------
# Private Endpoint for Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-keyvault-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "vnet-link-keyvault"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_a_record" "keyvault" {
  name                = azurerm_key_vault.main.name
  zone_name           = azurerm_private_dns_zone.keyvault.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address]
}
