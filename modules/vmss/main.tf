# =============================================================================
# VMSS Module - Caddy Cluster
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# SSH Key (if not provided)
# -----------------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  count     = var.admin_ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# -----------------------------------------------------------------------------
# User Assigned Managed Identity
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "vmss" {
  name                = "id-vmss-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Key Vault Access Policy for VMSS
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_access_policy" "vmss" {
  key_vault_id = var.keyvault_id
  tenant_id    = azurerm_user_assigned_identity.vmss.tenant_id
  object_id    = azurerm_user_assigned_identity.vmss.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# -----------------------------------------------------------------------------
# Cloud-Init Configuration
# -----------------------------------------------------------------------------
locals {
  # Determine Redis host without port for storage module
  redis_host_only = split(":", var.redis_host)[0]
  
  # Cloud-init configuration for Caddy setup
  cloud_init_config = templatefile("${path.module}/templates/cloud-init.yaml", {
    storage_account_name       = var.storage_account_name
    storage_account_key        = var.storage_account_key
    file_share_name            = var.file_share_name
    domain_name                = var.domain_name
    acme_email                 = var.acme_email
    upstream_servers           = join(",", var.upstream_servers)
    redis_host                 = local.redis_host_only
    redis_port                 = var.redis_port
    redis_password             = var.redis_password
    rate_limit_storage_backend = var.rate_limit_storage_backend
    caddy_config               = base64encode(templatefile("${path.module}/templates/caddy-config.json.tftpl", {
      domain_name                = var.domain_name
      acme_email                 = var.acme_email
      upstream_servers           = var.upstream_servers
      redis_host                 = local.redis_host_only
      redis_port                 = tostring(var.redis_port)
      redis_password             = var.redis_password
      rate_limit_storage_backend = var.rate_limit_storage_backend
    }))
    waf_config                 = base64encode(file("${path.module}/templates/coraza-config.conf"))
  })
}

# -----------------------------------------------------------------------------
# Virtual Machine Scale Set
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine_scale_set" "caddy" {
  name                = "vmss-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instance_count

  admin_username = var.admin_username

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key != "" ? var.admin_ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  }

  # User Assigned Identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vmss.id]
  }

  # Source image - Ubuntu 22.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # OS Disk
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 30
  }

  # Network Interface
  network_interface {
    name    = "nic-caddy"
    primary = true

    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = var.subnet_id
      load_balancer_backend_address_pool_ids = [var.lb_backend_pool_id]
    }
  }

  # Cloud-init
  custom_data = base64encode(local.cloud_init_config)

  # Upgrade policy
  upgrade_mode = "Manual"

  # Zones - disabled due to capacity constraints in eastus2
  # zones = ["1", "2"]
  # zone_balance = true

  # Extension - Azure Monitor Agent
  extension {
    name                       = "AzureMonitorLinuxAgent"
    publisher                  = "Microsoft.Azure.Monitor"
    type                       = "AzureMonitorLinuxAgent"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
  }

  # Extension - Application Health
  extension {
    name                       = "ApplicationHealthLinux"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true

    settings = jsonencode({
      protocol    = "http"
      port        = 80
      requestPath = "/health"
    })
  }

  tags = var.tags

  depends_on = [azurerm_key_vault_access_policy.vmss]

  lifecycle {
    ignore_changes = [
      instances,  # Allow autoscaling to manage instance count
    ]
  }
}

# -----------------------------------------------------------------------------
# Autoscale Settings (optional)
# -----------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "autoscale-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.caddy.id

  profile {
    name = "default"

    capacity {
      default = var.vmss_instance_count
      minimum = 2
      maximum = 10
    }

    # Scale out on CPU > 70%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.caddy.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in on CPU < 30%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.caddy.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}
