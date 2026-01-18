# =============================================================================
# VMSS Module - Outputs
# =============================================================================

output "vmss_id" {
  description = "ID of the VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.caddy.id
}

output "vmss_name" {
  description = "Name of the VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.caddy.name
}

output "vmss_identity_principal_id" {
  description = "Principal ID of the VMSS Managed Identity"
  value       = azurerm_user_assigned_identity.vmss.principal_id
}

output "vmss_identity_client_id" {
  description = "Client ID of the VMSS Managed Identity"
  value       = azurerm_user_assigned_identity.vmss.client_id
}

output "ssh_private_key" {
  description = "SSH private key (only if auto-generated)"
  value       = var.admin_ssh_public_key == "" ? tls_private_key.ssh[0].private_key_pem : null
  sensitive   = true
}

output "autoscale_setting_id" {
  description = "ID of the autoscale setting"
  value       = azurerm_monitor_autoscale_setting.vmss.id
}
