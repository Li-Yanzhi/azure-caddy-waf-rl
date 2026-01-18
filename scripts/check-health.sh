#!/bin/bash
# =============================================================================
# Health Check Script for Caddy Instances
# =============================================================================
# Checks health status of all VMSS instances
# =============================================================================

set -euo pipefail

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-caddy-cluster}"
VMSS_NAME="${VMSS_NAME:-}"
HEALTH_PATH="${HEALTH_PATH:-/health}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -g, --resource-group    Resource group name (default: rg-caddy-cluster)
    -v, --vmss-name         VMSS name (required)
    -p, --path              Health check path (default: /health)
    -h, --help              Show this help message

Example:
    $0 -g rg-caddy-cluster -v vmss-caddy-abc123
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
        -p|--path)
            HEALTH_PATH="$2"
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

if [[ -z "$VMSS_NAME" ]]; then
    log_error "VMSS name is required"
    usage
fi

# Get instances
log_info "Checking VMSS instances in $RESOURCE_GROUP/$VMSS_NAME..."
echo ""

INSTANCES=$(az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].{id:instanceId,state:provisioningState}" \
    --output json)

HEALTHY=0
UNHEALTHY=0
TOTAL=0

echo "$INSTANCES" | jq -c '.[]' | while read -r instance; do
    instance_id=$(echo "$instance" | jq -r '.id')
    state=$(echo "$instance" | jq -r '.state')
    TOTAL=$((TOTAL + 1))
    
    # Get private IP
    private_ip=$(az vmss nic list \
        --resource-group "$RESOURCE_GROUP" \
        --vmss-name "$VMSS_NAME" \
        --instance-id "$instance_id" \
        --query "[0].ipConfigurations[0].privateIPAddress" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$private_ip" ]]; then
        log_error "Instance $instance_id: Could not get IP (Provisioning: $state)"
        continue
    fi
    
    # Check health
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "azureuser@${private_ip}" \
        "curl -sf http://127.0.0.1${HEALTH_PATH}" > /dev/null 2>&1; then
        log_success "Instance $instance_id ($private_ip): Healthy"
        HEALTHY=$((HEALTHY + 1))
    else
        log_error "Instance $instance_id ($private_ip): Unhealthy"
        UNHEALTHY=$((UNHEALTHY + 1))
    fi
done

echo ""
echo "========================================"
echo "Summary: $HEALTHY healthy, $UNHEALTHY unhealthy"
echo "========================================"

if [[ $UNHEALTHY -gt 0 ]]; then
    exit 1
fi
