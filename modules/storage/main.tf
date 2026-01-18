# =============================================================================
# Storage Module - Storage Account + Azure Files
# =============================================================================
# Directory Structure:
#   /mnt/caddyshare/
#   ├── caddy-data/     # Certificates, ACME, OCSP (storage root)
#   ├── waf/
#   │   ├── crs/        # OWASP CRS rules
#   │   └── custom/     # Custom WAF rules
#   └── releases/       # Configuration versions (optional)
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
# Get current public IP for Terraform access
# -----------------------------------------------------------------------------
data "http" "my_ip" {
  url = "https://api.ipify.org?format=text"
}

# -----------------------------------------------------------------------------
# Storage Account
# -----------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  name                     = "stcaddy${var.suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true  # Needed for SMB mount

  # Network rules - Allow during deployment, lock down after
  # Run: az storage account update -n stcaddyXXXXXX -g rg-caddy-cluster --default-action Deny
  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.subnet_id]
  }

  tags = merge(var.tags, {
    SecurityControl = "Ignore"
  })
}

# -----------------------------------------------------------------------------
# Azure Files Share
# -----------------------------------------------------------------------------
resource "azurerm_storage_share" "caddy" {
  name                 = "caddyshare"
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.file_share_quota_gb
  access_tier          = "TransactionOptimized"  # Good for frequent small file ops

  # Enable SMB settings
  acl {
    id = "caddy-access"
    access_policy {
      permissions = "rwdl"
    }
  }
}

# -----------------------------------------------------------------------------
# Directory Structure - Created via Azure Files directories
# -----------------------------------------------------------------------------
resource "azurerm_storage_share_directory" "caddy_data" {
  name             = "caddy-data"
  storage_share_id = azurerm_storage_share.caddy.id
}

resource "azurerm_storage_share_directory" "waf" {
  name             = "waf"
  storage_share_id = azurerm_storage_share.caddy.id
}

resource "azurerm_storage_share_directory" "waf_crs" {
  name             = "waf/crs"
  storage_share_id = azurerm_storage_share.caddy.id

  depends_on = [azurerm_storage_share_directory.waf]
}

resource "azurerm_storage_share_directory" "waf_custom" {
  name             = "waf/custom"
  storage_share_id = azurerm_storage_share.caddy.id

  depends_on = [azurerm_storage_share_directory.waf]
}

resource "azurerm_storage_share_directory" "releases" {
  name             = "releases"
  storage_share_id = azurerm_storage_share.caddy.id
}

# -----------------------------------------------------------------------------
# Private Endpoint for Storage (optional but recommended)
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Storage
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "vnet-link-storage"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.main.name
  zone_name           = azurerm_private_dns_zone.storage.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}
