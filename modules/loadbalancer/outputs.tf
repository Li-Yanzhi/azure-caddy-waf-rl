# =============================================================================
# Load Balancer Module - Outputs
# =============================================================================

output "lb_id" {
  description = "ID of the Load Balancer"
  value       = azurerm_lb.main.id
}

output "lb_name" {
  description = "Name of the Load Balancer"
  value       = azurerm_lb.main.name
}

output "backend_pool_id" {
  description = "ID of the backend address pool"
  value       = azurerm_lb_backend_address_pool.caddy.id
}

output "backend_pool_name" {
  description = "Name of the backend address pool"
  value       = azurerm_lb_backend_address_pool.caddy.name
}

output "http_probe_id" {
  description = "ID of the HTTP health probe"
  value       = azurerm_lb_probe.http.id
}

output "https_probe_id" {
  description = "ID of the HTTPS health probe"
  value       = azurerm_lb_probe.https.id
}

output "frontend_ip_configuration" {
  description = "Frontend IP configuration"
  value = {
    name = azurerm_lb.main.frontend_ip_configuration[0].name
    id   = azurerm_lb.main.frontend_ip_configuration[0].id
  }
}
