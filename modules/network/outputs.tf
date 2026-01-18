# =============================================================================
# Network Module - Outputs
# =============================================================================

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "ID of the Caddy subnet"
  value       = azurerm_subnet.caddy.id
}

output "subnet_name" {
  description = "Name of the Caddy subnet"
  value       = azurerm_subnet.caddy.name
}

output "nsg_id" {
  description = "ID of the Network Security Group"
  value       = azurerm_network_security_group.caddy.id
}

output "public_ip_id" {
  description = "ID of the Public IP"
  value       = azurerm_public_ip.lb.id
}

output "public_ip_address" {
  description = "Public IP address"
  value       = azurerm_public_ip.lb.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the Public IP"
  value       = azurerm_public_ip.lb.fqdn
}

output "ddos_protection_plan_id" {
  description = "ID of the DDoS Protection Plan"
  value       = var.enable_ddos_protection ? azurerm_network_ddos_protection_plan.main[0].id : null
}
