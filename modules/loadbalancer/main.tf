# =============================================================================
# Load Balancer Module - Standard Public LB
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
# Standard Load Balancer
# -----------------------------------------------------------------------------
resource "azurerm_lb" "main" {
  name                = "lb-caddy-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = var.public_ip_id
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Backend Pool
# -----------------------------------------------------------------------------
resource "azurerm_lb_backend_address_pool" "caddy" {
  name            = "backend-caddy"
  loadbalancer_id = azurerm_lb.main.id
}

# -----------------------------------------------------------------------------
# Health Probes
# -----------------------------------------------------------------------------
# HTTP Health Probe (推荐 - 应用级健康检查)
resource "azurerm_lb_probe" "http" {
  name                = "probe-http-health"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Http"
  port                = 80
  request_path        = "/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# HTTPS Health Probe (可选)
resource "azurerm_lb_probe" "https" {
  name                = "probe-https-health"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Https"
  port                = 443
  request_path        = "/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# TCP Probe as fallback
resource "azurerm_lb_probe" "tcp_443" {
  name                = "probe-tcp-443"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Tcp"
  port                = 443
  interval_in_seconds = 5
  number_of_probes    = 2
}

# -----------------------------------------------------------------------------
# Load Balancing Rules
# -----------------------------------------------------------------------------
# HTTP Rule (80) - 用于 ACME HTTP-01 challenge 或重定向到 HTTPS
resource "azurerm_lb_rule" "http" {
  name                           = "rule-http"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.caddy.id]
  probe_id                       = azurerm_lb_probe.http.id
  
  # Session persistence (可选，根据需求调整)
  load_distribution              = "Default"  # None, SourceIP, SourceIPProtocol
  
  # Enable TCP Reset on idle
  enable_tcp_reset               = true
  idle_timeout_in_minutes        = 4
  
  # Disable floating IP (Direct Server Return)
  enable_floating_ip             = false
  
  # Must disable SNAT when using outbound rules on the same frontend IP
  disable_outbound_snat          = true
}

# HTTPS Rule (443)
resource "azurerm_lb_rule" "https" {
  name                           = "rule-https"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.caddy.id]
  # Use TCP probe instead of HTTPS to avoid certificate issues with health checks
  probe_id                       = azurerm_lb_probe.tcp_443.id
  
  load_distribution              = "Default"
  enable_tcp_reset               = true
  idle_timeout_in_minutes        = 4
  enable_floating_ip             = false
  
  # Must disable SNAT when using outbound rules on the same frontend IP
  disable_outbound_snat          = true
}

# -----------------------------------------------------------------------------
# Outbound Rules (for SNAT)
# -----------------------------------------------------------------------------
resource "azurerm_lb_outbound_rule" "main" {
  name                    = "outbound-rule"
  loadbalancer_id         = azurerm_lb.main.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.caddy.id

  frontend_ip_configuration {
    name = "frontend"
  }

  # Outbound ports per instance
  allocated_outbound_ports = 1024
  idle_timeout_in_minutes  = 4
  enable_tcp_reset         = true
}
