# =============================================================================
# Storage Module - Outputs
# =============================================================================

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_key" {
  description = "Primary access key for the Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "file_share_id" {
  description = "ID of the Azure Files share"
  value       = azurerm_storage_share.caddy.id
}

output "file_share_name" {
  description = "Name of the Azure Files share"
  value       = azurerm_storage_share.caddy.name
}

output "file_share_url" {
  description = "URL of the Azure Files share"
  value       = azurerm_storage_share.caddy.url
}

output "private_endpoint_ip" {
  description = "Private IP address of the storage private endpoint"
  value       = azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address
}

# SMB mount command for reference
output "smb_mount_command" {
  description = "Command to mount the Azure Files share via SMB"
  value       = <<-EOT
    # Install cifs-utils if not present
    sudo apt-get update && sudo apt-get install -y cifs-utils
    
    # Create mount point
    sudo mkdir -p /mnt/caddyshare
    
    # Create credentials file
    sudo bash -c 'cat > /etc/smbcredentials/${azurerm_storage_account.main.name}.cred << EOF
    username=${azurerm_storage_account.main.name}
    password=<storage_account_key>
    EOF'
    sudo chmod 600 /etc/smbcredentials/${azurerm_storage_account.main.name}.cred
    
    # Mount the share
    sudo mount -t cifs //${azurerm_storage_account.main.name}.file.core.windows.net/${azurerm_storage_share.caddy.name} /mnt/caddyshare \
      -o credentials=/etc/smbcredentials/${azurerm_storage_account.main.name}.cred,dir_mode=0755,file_mode=0644,serverino,nosharesock,actimeo=30
    
    # Add to fstab for persistence
    echo "//${azurerm_storage_account.main.name}.file.core.windows.net/${azurerm_storage_share.caddy.name} /mnt/caddyshare cifs credentials=/etc/smbcredentials/${azurerm_storage_account.main.name}.cred,dir_mode=0755,file_mode=0644,serverino,nosharesock,actimeo=30 0 0" | sudo tee -a /etc/fstab
  EOT
  sensitive   = false
}
