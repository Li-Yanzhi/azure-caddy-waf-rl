#!/bin/bash
# =============================================================================
# Deploy OWASP CRS Rules to Azure Files Share
# =============================================================================
# This script downloads and deploys OWASP Core Rule Set to the shared storage
# =============================================================================

set -euo pipefail

# Configuration
CRS_VERSION="${CRS_VERSION:-4.0.0}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
FILE_SHARE="${FILE_SHARE:-caddyshare}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/caddyshare}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -v, --version           CRS version (default: 4.0.0)
    -s, --storage-account   Azure Storage Account name (required)
    -f, --file-share        File share name (default: caddyshare)
    -m, --mount-point       Mount point (default: /mnt/caddyshare)
    -h, --help              Show this help message

Example:
    $0 -s mystorageaccount -v 4.0.0
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            CRS_VERSION="$2"
            shift 2
            ;;
        -s|--storage-account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -f|--file-share)
            FILE_SHARE="$2"
            shift 2
            ;;
        -m|--mount-point)
            MOUNT_POINT="$2"
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

if [[ -z "$STORAGE_ACCOUNT" ]]; then
    log_error "Storage account is required"
    usage
fi

# Check if mount point exists
if [[ ! -d "$MOUNT_POINT" ]]; then
    log_error "Mount point does not exist: $MOUNT_POINT"
    exit 1
fi

# Create working directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

log_info "Downloading OWASP CRS v${CRS_VERSION}..."

# Download CRS
cd "$WORK_DIR"
curl -sSL "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz" | tar -xz

CRS_DIR="coreruleset-${CRS_VERSION}"

if [[ ! -d "$CRS_DIR" ]]; then
    log_error "Failed to extract CRS"
    exit 1
fi

# Create version-specific directory
TARGET_DIR="${MOUNT_POINT}/waf/crs"
VERSIONED_DIR="${TARGET_DIR}/v${CRS_VERSION}"

log_info "Deploying to ${TARGET_DIR}..."

# Backup existing rules
if [[ -d "$TARGET_DIR" ]] && [[ "$(ls -A $TARGET_DIR 2>/dev/null)" ]]; then
    BACKUP_DIR="${MOUNT_POINT}/waf/crs-backup-$(date +%Y%m%d-%H%M%S)"
    log_info "Backing up existing rules to $BACKUP_DIR..."
    mv "$TARGET_DIR" "$BACKUP_DIR"
fi

# Create target directory
mkdir -p "$TARGET_DIR"

# Copy rules
cp -r "${CRS_DIR}/rules/"* "$TARGET_DIR/"
cp "${CRS_DIR}/crs-setup.conf.example" "$TARGET_DIR/crs-setup.conf"

# Create custom crs-setup.conf with recommended settings
cat > "${TARGET_DIR}/crs-setup.conf" << 'EOF'
# =============================================================================
# OWASP CRS Configuration
# =============================================================================

# -- Paranoia Level --
# Level 1 (default) - Minimal rules, few false positives
# Level 2 - Additional rules for more protection
# Level 3 - More aggressive rules
# Level 4 - Maximum protection (many false positives)
SecAction "id:900000,phase:1,pass,t:none,nolog,setvar:tx.paranoia_level=1"

# -- Executing Paranoia Level --
SecAction "id:900001,phase:1,pass,t:none,nolog,setvar:tx.executing_paranoia_level=1"

# -- Anomaly Scoring Mode --
SecAction "id:900110,phase:1,pass,t:none,nolog,\
    setvar:tx.inbound_anomaly_score_threshold=5,\
    setvar:tx.outbound_anomaly_score_threshold=4"

# -- Early Blocking --
SecAction "id:900120,phase:1,pass,t:none,nolog,setvar:tx.early_blocking=0"

# -- Application Specific Rule Exclusions --
# Uncomment and modify based on your application
# SecAction "id:900130,phase:1,pass,t:none,nolog,setvar:tx.crs_exclusions_wordpress=1"
# SecAction "id:900130,phase:1,pass,t:none,nolog,setvar:tx.crs_exclusions_drupal=1"
# SecAction "id:900130,phase:1,pass,t:none,nolog,setvar:tx.crs_exclusions_nextcloud=1"

# -- Reporting Level --
SecAction "id:900200,phase:1,pass,t:none,nolog,setvar:tx.reporting_level=4"

# -- HTTP Policy Settings --
SecAction "id:900220,phase:1,pass,t:none,nolog,\
    setvar:'tx.allowed_methods=GET HEAD POST OPTIONS PUT PATCH DELETE',\
    setvar:'tx.allowed_request_content_type=|application/x-www-form-urlencoded| |multipart/form-data| |multipart/related| |text/xml| |application/xml| |application/soap+xml| |application/json| |application/cloudevents+json| |application/cloudevents-batch+json|',\
    setvar:'tx.allowed_http_versions=HTTP/1.0 HTTP/1.1 HTTP/2 HTTP/2.0'"

# -- File Upload Limits --
SecAction "id:900300,phase:1,pass,t:none,nolog,\
    setvar:tx.max_num_args=255,\
    setvar:tx.arg_name_length=100,\
    setvar:tx.arg_length=400,\
    setvar:tx.total_arg_length=64000,\
    setvar:tx.max_file_size=1048576,\
    setvar:tx.combined_file_sizes=1048576"

# -- Sampling --
SecAction "id:900400,phase:1,pass,t:none,nolog,setvar:tx.sampling_percentage=100"
EOF

log_success "OWASP CRS v${CRS_VERSION} deployed successfully!"
log_info "Rules location: ${TARGET_DIR}"
log_info ""
log_info "Next steps:"
log_info "1. Review and customize ${TARGET_DIR}/crs-setup.conf"
log_info "2. Add custom exclusions to ${MOUNT_POINT}/waf/custom/"
log_info "3. Run rolling update to reload Caddy configuration"
