# =============================================================================
# Key Vault Module - Outputs
# =============================================================================

output "keyvault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "keyvault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "keyvault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "cloudflare_api_token_secret_id" {
  description = "ID of the Cloudflare API token secret"
  value       = var.cloudflare_api_token != "" ? azurerm_key_vault_secret.cloudflare_api_token[0].id : null
}

output "cloudflare_api_token_secret_name" {
  description = "Name of the Cloudflare API token secret"
  value       = var.cloudflare_api_token != "" ? azurerm_key_vault_secret.cloudflare_api_token[0].name : null
}

output "private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
}
