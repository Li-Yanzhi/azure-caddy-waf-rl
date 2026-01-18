#!/bin/bash
# =============================================================================
# WAF Mode Switch Script
# =============================================================================
# Switches WAF between DetectionOnly and On (blocking) mode
# =============================================================================

set -euo pipefail

# Configuration
MOUNT_POINT="${MOUNT_POINT:-/mnt/caddyshare}"
CORAZA_CONFIG="${CORAZA_CONFIG:-/etc/caddy/coraza.conf}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 <mode>

Modes:
    detection   Switch to DetectionOnly mode (log only, no blocking)
    blocking    Switch to On mode (active blocking)
    status      Show current mode

Example:
    $0 detection    # Enable detection mode
    $0 blocking     # Enable blocking mode
    $0 status       # Check current mode
EOF
    exit 1
}

get_current_mode() {
    if grep -q "^SecRuleEngine On" "$CORAZA_CONFIG" 2>/dev/null; then
        echo "blocking"
    elif grep -q "^SecRuleEngine DetectionOnly" "$CORAZA_CONFIG" 2>/dev/null; then
        echo "detection"
    else
        echo "unknown"
    fi
}

set_mode() {
    local mode=$1
    local config_value
    
    case $mode in
        detection)
            config_value="DetectionOnly"
            ;;
        blocking)
            config_value="On"
            ;;
        *)
            log_error "Invalid mode: $mode"
            exit 1
            ;;
    esac
    
    # Backup current config
    cp "$CORAZA_CONFIG" "${CORAZA_CONFIG}.backup"
    
    # Update mode
    sed -i "s/^SecRuleEngine .*/SecRuleEngine $config_value/" "$CORAZA_CONFIG"
    
    log_success "WAF mode set to: $mode ($config_value)"
    log_info "Backup saved to: ${CORAZA_CONFIG}.backup"
    log_warn "Remember to run rolling-update.sh to apply changes to all instances!"
}

# Main
if [[ $# -lt 1 ]]; then
    usage
fi

case $1 in
    detection|blocking)
        current=$(get_current_mode)
        log_info "Current mode: $current"
        set_mode "$1"
        ;;
    status)
        current=$(get_current_mode)
        echo "Current WAF mode: $current"
        case $current in
            detection)
                log_info "WAF is in DETECTION mode - logging only, no blocking"
                ;;
            blocking)
                log_warn "WAF is in BLOCKING mode - actively blocking malicious requests"
                ;;
            *)
                log_error "Could not determine WAF mode"
                ;;
        esac
        ;;
    *)
        usage
        ;;
esac
