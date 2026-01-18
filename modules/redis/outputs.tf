# =============================================================================
# Redis Module - Outputs
# =============================================================================

output "redis_id" {
  description = "ID of the Azure Cache for Redis"
  value       = azurerm_redis_cache.main.id
}

output "redis_name" {
  description = "Name of the Azure Cache for Redis"
  value       = azurerm_redis_cache.main.name
}

output "redis_hostname" {
  description = "Hostname of the Redis cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_ssl_port" {
  description = "SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_access_key" {
  description = "Primary access key for Redis"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_primary_connection_string" {
  description = "Primary connection string for Redis"
  value       = azurerm_redis_cache.main.primary_connection_string
  sensitive   = true
}

output "redis_private_ip" {
  description = "Private IP address of the Redis private endpoint"
  value       = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
}
