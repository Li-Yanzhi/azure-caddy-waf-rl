# =============================================================================
# Network Module - VNet, Subnet, NSG, DDoS Protection, Public IP
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
# DDoS Protection Plan
# -----------------------------------------------------------------------------
resource "azurerm_network_ddos_protection_plan" "main" {
  count = var.enable_ddos_protection ? 1 : 0

  name                = "ddos-protection-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.main[0].id
      enable = true
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Subnet for Caddy VMSS
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "caddy" {
  name                 = "snet-caddy"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]

  # Disable network policies for Private Endpoints to allow traffic flow
  private_endpoint_network_policies = "Disabled"

  lifecycle {
    ignore_changes = [
      default_outbound_access_enabled
    ]
  }
}

# -----------------------------------------------------------------------------
# Network Security Group
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "caddy" {
  name                = "nsg-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Allow HTTP from Internet (via LB)
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS from Internet (via LB)
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH from VNet (for management, consider restricting further)
  security_rule {
    name                       = "AllowSSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow Azure Load Balancer health probes
  security_rule {
    name                       = "AllowAzureLB"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Allow SMB for Azure Files (within VNet)
  security_rule {
    name                       = "AllowSMB"
    priority                   = 400
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "445"
    source_address_prefix      = "*"
    destination_address_prefix = "Storage"
  }

  # Allow Redis for distributed rate limiting (VNet internal)
  security_rule {
    name                       = "AllowRedis"
    priority                   = 410
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6380"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  # Deny all other inbound
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# NSG Association
# -----------------------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "caddy" {
  subnet_id                 = azurerm_subnet.caddy.id
  network_security_group_id = azurerm_network_security_group.caddy.id
}

# -----------------------------------------------------------------------------
# Public IP for Load Balancer
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "lb" {
  name                = "pip-caddy-lb-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  
  # For DDoS protection, Standard SKU is required
  # DDoS Protection is associated at VNet level

  domain_name_label = "caddy-${var.suffix}"

  tags = var.tags
}
