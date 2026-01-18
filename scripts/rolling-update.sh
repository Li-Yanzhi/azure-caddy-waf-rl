#!/bin/bash
# =============================================================================
# Rolling Update Script for Caddy Cluster
# =============================================================================
# This script performs zero-downtime configuration updates across the VMSS
# by updating one instance at a time using the Caddy Admin API
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-caddy-cluster}"
VMSS_NAME="${VMSS_NAME:-}"
CONFIG_FILE="${CONFIG_FILE:-config.json}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/health}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
PAUSE_BETWEEN_INSTANCES="${PAUSE_BETWEEN_INSTANCES:-10}"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -g, --resource-group    Resource group name (default: rg-caddy-cluster)
    -v, --vmss-name         VMSS name (required if not set via env)
    -c, --config-file       Path to Caddy config JSON file (default: config.json)
    -t, --timeout           Health check timeout in seconds (default: 30)
    -p, --pause             Pause between instances in seconds (default: 10)
    -h, --help              Show this help message

Environment Variables:
    RESOURCE_GROUP          Resource group name
    VMSS_NAME               VMSS name
    CONFIG_FILE             Config file path

Example:
    $0 -g rg-caddy-cluster -v vmss-caddy-abc123 -c new-config.json
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -v|--vmss-name)
            VMSS_NAME="$2"
            shift 2
            ;;
        -c|--config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -t|--timeout)
            HEALTH_CHECK_TIMEOUT="$2"
            shift 2
            ;;
        -p|--pause)
            PAUSE_BETWEEN_INSTANCES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$VMSS_NAME" ]]; then
    log_error "VMSS name is required. Use -v or --vmss-name or set VMSS_NAME env variable"
    usage
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Validate JSON
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_error "Invalid JSON in config file: $CONFIG_FILE"
    exit 1
fi

log_info "Starting rolling update..."
log_info "Resource Group: $RESOURCE_GROUP"
log_info "VMSS Name: $VMSS_NAME"
log_info "Config File: $CONFIG_FILE"

# Get VMSS instance IDs
log_info "Fetching VMSS instances..."
INSTANCE_IDS=$(az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].instanceId" \
    --output tsv)

if [[ -z "$INSTANCE_IDS" ]]; then
    log_error "No VMSS instances found"
    exit 1
fi

INSTANCE_COUNT=$(echo "$INSTANCE_IDS" | wc -l)
log_info "Found $INSTANCE_COUNT instance(s)"

# Function to get instance private IP
get_instance_ip() {
    local instance_id=$1
    az vmss nic list \
        --resource-group "$RESOURCE_GROUP" \
        --vmss-name "$VMSS_NAME" \
        --instance-id "$instance_id" \
        --query "[0].ipConfigurations[0].privateIPAddress" \
        --output tsv
}

# Function to update instance via SSH
update_instance() {
    local instance_id=$1
    local private_ip=$2
    
    log_info "Updating instance $instance_id ($private_ip)..."
    
    # Copy config to instance (assumes SSH access is configured)
    scp -o StrictHostKeyChecking=no "$CONFIG_FILE" "azureuser@${private_ip}:/tmp/new-config.json"
    
    # Execute update via Caddy Admin API
    ssh -o StrictHostKeyChecking=no "azureuser@${private_ip}" << 'REMOTE_SCRIPT'
        set -e
        
        # Backup current config
        if [[ -f /etc/caddy/config.json ]]; then
            cp /etc/caddy/config.json /etc/caddy/config.json.backup
        fi
        
        # Copy new config
        sudo cp /tmp/new-config.json /etc/caddy/config.json
        sudo chown caddy:caddy /etc/caddy/config.json
        
        # Load via Admin API
        if curl -sf -X PUT "http://127.0.0.1:2019/load" \
            -H "Content-Type: application/json" \
            -H "Cache-Control: must-revalidate" \
            -d @/etc/caddy/config.json; then
            echo "Configuration loaded successfully"
        else
            echo "Failed to load configuration, rolling back..."
            if [[ -f /etc/caddy/config.json.backup ]]; then
                sudo cp /etc/caddy/config.json.backup /etc/caddy/config.json
                curl -sf -X PUT "http://127.0.0.1:2019/load" \
                    -H "Content-Type: application/json" \
                    -d @/etc/caddy/config.json
            fi
            exit 1
        fi
        
        # Cleanup
        rm -f /tmp/new-config.json
REMOTE_SCRIPT
}

# Function to check instance health
check_instance_health() {
    local private_ip=$1
    local timeout=$2
    local start_time=$(date +%s)
    
    while true; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "azureuser@${private_ip}" \
            "curl -sf http://127.0.0.1${HEALTH_CHECK_PATH}" > /dev/null 2>&1; then
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        
        sleep 2
    done
}

# Main update loop
UPDATED=0
FAILED=0

for instance_id in $INSTANCE_IDS; do
    log_info "Processing instance $instance_id ($((UPDATED + 1))/$INSTANCE_COUNT)..."
    
    # Get instance IP
    private_ip=$(get_instance_ip "$instance_id")
    
    if [[ -z "$private_ip" ]]; then
        log_error "Could not get IP for instance $instance_id"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Update instance
    if update_instance "$instance_id" "$private_ip"; then
        log_info "Waiting for health check..."
        
        if check_instance_health "$private_ip" "$HEALTH_CHECK_TIMEOUT"; then
            log_success "Instance $instance_id updated and healthy"
            UPDATED=$((UPDATED + 1))
        else
            log_error "Instance $instance_id failed health check"
            FAILED=$((FAILED + 1))
        fi
    else
        log_error "Failed to update instance $instance_id"
        FAILED=$((FAILED + 1))
    fi
    
    # Pause before next instance (except for last one)
    if [[ $((UPDATED + FAILED)) -lt $INSTANCE_COUNT ]]; then
        log_info "Pausing for $PAUSE_BETWEEN_INSTANCES seconds before next instance..."
        sleep "$PAUSE_BETWEEN_INSTANCES"
    fi
done

# Summary
echo ""
log_info "========================================"
log_info "Rolling Update Summary"
log_info "========================================"
log_info "Total instances: $INSTANCE_COUNT"
log_success "Successfully updated: $UPDATED"
if [[ $FAILED -gt 0 ]]; then
    log_error "Failed: $FAILED"
    exit 1
else
    log_success "All instances updated successfully!"
fi
