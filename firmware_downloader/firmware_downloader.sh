#!/bin/bash

# Configuration
REPO_MESH="meshcore-dev/MeshCore"
REPO_BOOT="oltaco/Adafruit_nRF52_Bootloader_OTAFIX"

FIRMWARES=("repeater" "companion-ble" "companion-usb" "room-server")

# Absolute paths
PARENT_DIR="/opt/firmware_downloader"
MESH_BASE="$PARENT_DIR/MeshCore"
BOOT_BASE="$PARENT_DIR/Adafruit_nRF52_Bootloader_OTAFIX"
LOG_FILE="/var/log/firmware_downloader.log"

# Create directories and log file
mkdir -p "$MESH_BASE" "$BOOT_BASE"
touch "$LOG_FILE" 2>/dev/null

# Logging function (outputs to stdout for journalctl and appends to LOG_FILE)
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

# Check for jq
if ! command -v jq &> /dev/null; then
    log "ERROR" "jq is not installed. Please install it (sudo apt install jq)"
    exit 1
fi

# Check for --force flag
FORCE=0
if [[ "$1" == "--force" ]]; then
    FORCE=1
    log "INFO" "Force flag detected. All assets will be re-processed."
fi

# =========================================================
# SECTION 1: MESHCORE FIRMWARES
# =========================================================
log "INFO" "--- Starting MeshCore firmware update process ---"

for fw in "${FIRMWARES[@]}"; do
    log "INFO" "Processing MeshCore component: $fw"

    # Determine release search pattern
    if [[ $fw == companion-* ]]; then
        release_pattern="Companion Firmware"
        type_filter="${fw#companion-}"
    elif [[ $fw == repeater ]]; then
        release_pattern="Repeater Firmware"
        type_filter=""
    elif [[ $fw == room-server ]]; then
        release_pattern="Room Server Firmware"
        type_filter=""
    fi

    # Get latest release tag from GitHub API
    latest_tag=$(curl -s "https://api.github.com/repos/$REPO_MESH/releases" \
        | jq -r ".[] | select(.name | test(\"$release_pattern\"; \"i\")) | .name" \
        | sort -V | tail -n1)

    if [ -z "$latest_tag" ]; then
        log "WARNING" "No release found for $fw"
        continue
    fi

    fw_dir="$MESH_BASE/$fw/$latest_tag"
    latest_link_dir="$MESH_BASE/$fw/latest"

    # Download Section
    if [ ! -d "$fw_dir" ] || [ $FORCE -eq 1 ]; then
        mkdir -p "$fw_dir"
        log "INFO" "Downloading $fw assets for version $latest_tag..."
        urls=$(curl -s "https://api.github.com/repos/$REPO_MESH/releases" \
            | jq -r ".[] | select(.name==\"$latest_tag\") | .assets[] | .browser_download_url")

        for url in $urls; do
            filename=$(basename "$url")
            [[ $filename != *.zip ]] && continue
            [[ -n $type_filter && $filename != *"$type_filter"* ]] && continue

            log "INFO" "Downloading $filename..."
            curl -L -s -o "$fw_dir/$filename" "$url"
        done
    else
        log "INFO" "Directory $fw_dir already exists. Skipping download."
    fi

    # Symlink Section
    mkdir -p "$latest_link_dir"
    shopt -s nullglob
    for file_path in "$fw_dir"/*.zip; do
        filename=$(basename "$file_path")
        # Removes version strings like -v1.2.3 or -v1.0.0-6d32
        link_name=$(echo "$filename" | sed -E 's/-v[0-9].*(\.zip)$/\1/')
        ln -sf "../$latest_tag/$filename" "$latest_link_dir/$link_name"
        log "INFO" "Symlinked MeshCore: $link_name -> $latest_tag/$filename"
    done
    shopt -u nullglob
done

# =========================================================
# SECTION 2: OLTACO BOOTLOADER
# =========================================================
log "INFO" "--- Starting Oltaco Bootloader update process ---"

# Get the latest release (ignoring names, just taking the most recent tag)
latest_boot_tag=$(curl -s "https://api.github.com/repos/$REPO_BOOT/releases" | jq -r ".[0].tag_name")

if [ -n "$latest_boot_tag" ] && [ "$latest_boot_tag" != "null" ]; then
    boot_dir="$BOOT_BASE/$latest_boot_tag"
    boot_latest_link_dir="$BOOT_BASE/latest"

    if [ ! -d "$boot_dir" ] || [ $FORCE -eq 1 ]; then
        mkdir -p "$boot_dir"
        log "INFO" "Downloading Bootloader assets for version $latest_boot_tag..."
        # Get all zip assets from that specific tag
        boot_urls=$(curl -s "https://api.github.com/repos/$REPO_BOOT/releases/tags/$latest_boot_tag" \
            | jq -r ".assets[] | select(.name | endswith(\".zip\")) | .browser_download_url")

        for url in $boot_urls; do
            filename=$(basename "$url")
            log "INFO" "Downloading bootloader file: $filename"
            curl -L -s -o "$boot_dir/$filename" "$url"
        done
    else
        log "INFO" "Bootloader version $latest_boot_tag already exists. Skipping download."
    fi

    # Symlink Section for Bootloader
    mkdir -p "$boot_latest_link_dir"
    shopt -s nullglob
    for file_path in "$boot_dir"/*.zip; do
        filename=$(basename "$file_path")
        # Handles both "-v0.6.0.zip" and "-0.6.0.zip"
        link_name=$(echo "$filename" | sed -E 's/-v?[0-9].*(\.zip)$/\1/')
        ln -sf "../$latest_boot_tag/$filename" "$boot_latest_link_dir/$link_name"
        log "INFO" "Symlinked Bootloader: $link_name -> $latest_boot_tag/$filename"
    done
    shopt -u nullglob
else
    log "ERROR" "Failed to retrieve latest release tag for Oltaco Bootloader."
fi

log "INFO" "Update process finished."
