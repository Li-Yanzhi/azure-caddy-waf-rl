# =============================================================================
# Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "public_ip_address" {
  description = "Public IP address of the Load Balancer"
  value       = module.network.public_ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the Public IP (if DNS label is set)"
  value       = module.network.public_ip_fqdn
}

output "load_balancer_id" {
  description = "ID of the Load Balancer"
  value       = module.loadbalancer.lb_id
}

output "vmss_id" {
  description = "ID of the VMSS"
  value       = module.vmss.vmss_id
}

output "vmss_identity_principal_id" {
  description = "Principal ID of the VMSS Managed Identity"
  value       = module.vmss.vmss_identity_principal_id
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = module.storage.storage_account_name
}

output "file_share_url" {
  description = "URL of the Azure Files share"
  value       = module.storage.file_share_url
}

output "keyvault_uri" {
  description = "URI of the Key Vault"
  value       = module.keyvault.keyvault_uri
}

output "ddos_protection_plan_id" {
  description = "ID of the DDoS Protection Plan (if enabled)"
  value       = module.network.ddos_protection_plan_id
}

output "redis_hostname" {
  description = "Hostname of the Azure Cache for Redis"
  value       = module.redis.redis_hostname
}

output "redis_ssl_port" {
  description = "SSL port of Redis"
  value       = module.redis.redis_ssl_port
}

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------
output "deployment_info" {
  description = "Deployment information and next steps"
  value = <<-EOT
    
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                        Caddy Cluster Deployment Info                          ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║                                                                               ║
    ║  Public IP: ${module.network.public_ip_address}
    ║                                                                               ║
    ║  DNS Setup:                                                                   ║
    ║  - Point your domain to the Public IP above                                   ║
    ║  - If using Cloudflare, ensure API token is configured                        ║
    ║                                                                               ║
    ║  Azure Files Mount Path: /mnt/caddyshare                                      ║
    ║  - caddy-data/    : Certificates, ACME data                                   ║
    ║  - waf/crs/       : OWASP CRS rules                                           ║
    ║  - waf/custom/    : Custom WAF rules                                          ║
    ║  - releases/      : Configuration versions                                    ║
    ║                                                                               ║
    ║  Rolling Update:                                                              ║
    ║  - Use scripts/rolling-update.sh for configuration updates                    ║
    ║  - Caddy Admin API: http://127.0.0.1:2019 (localhost only)                    ║
    ║                                                                               ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
    
  EOT
}
