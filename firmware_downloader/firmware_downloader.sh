#!/bin/bash

# Configuration
REPO="meshcore-dev/MeshCore"
FIRMWARES=("repeater" "companion-ble" "companion-usb" "room-server")
# Absolute path is required for systemd
BASE_DIR="/opt/firmware_downloader/MeshCore"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it (sudo apt install jq)"
    exit 1
fi

# Check for --force flag
FORCE=0
if [[ "$1" == "--force" ]]; then
    FORCE=1
fi

mkdir -p "$BASE_DIR"

for fw in "${FIRMWARES[@]}"; do
    echo "------------------------------------------------"
    echo "Processing firmware: $fw"

    # Determine release search pattern
    if [[ $fw == companion-* ]]; then
        release_pattern="Companion Firmware"
        type_filter="${fw#companion-}"  # ble or usb
    elif [[ $fw == repeater ]]; then
        release_pattern="Repeater Firmware"
        type_filter=""
    elif [[ $fw == room-server ]]; then
        release_pattern="Room Server Firmware"
        type_filter=""
    fi

    # Get latest release tag
    latest_tag=$(curl -s "https://api.github.com/repos/$REPO/releases" \
        | jq -r ".[] | select(.name | test(\"$release_pattern\"; \"i\")) | .name" \
        | sort -V \
        | tail -n1)

    if [ -z "$latest_tag" ]; then
        echo "No release found for $fw"
        continue
    fi

    echo "Latest release tag: $latest_tag"

    # Define directories
    fw_dir="$BASE_DIR/$fw/$latest_tag"
    latest_link_dir="$BASE_DIR/$fw/latest"

    # Check if download is needed
    download_needed=1
    if [ -d "$fw_dir" ] && [ $FORCE -eq 0 ]; then
        echo "Latest version directory already exists at $fw_dir."
        download_needed=0
    else
        mkdir -p "$fw_dir"
    fi

    # --- DOWNLOAD SECTION ---
    if [ $download_needed -eq 1 ] || [ $FORCE -eq 1 ]; then
        urls=$(curl -s "https://api.github.com/repos/$REPO/releases" \
            | jq -r ".[] | select(.name==\"$latest_tag\") | .assets[] | .browser_download_url")

        for url in $urls; do
            filename=$(basename "$url")
            # Filter for .zip and type if applicable
            if [[ $filename != *.zip ]]; then continue; fi
            if [[ -n $type_filter && $filename != *"$type_filter"* ]]; then continue; fi

            echo "Downloading $filename ..."
            curl -L -o "$fw_dir/$filename" "$url"
        done
    fi

    # --- SYMLINK SECTION ---
    echo "Updating symlinks in 'latest' folder..."
    mkdir -p "$latest_link_dir"

    if [ -d "$fw_dir" ]; then
        for file_path in "$fw_dir"/*.zip; do
            if [ -e "$file_path" ]; then
                filename=$(basename "$file_path")

                # CLEAN NAME LOGIC:
                # Use sed to replace "-v[digit]..." until the end of the file with just ".zip"
                # Input:  Heltec_..._usb-v1.11.0-6d32193.zip
                # Output: Heltec_..._usb.zip
                link_name=$(echo "$filename" | sed -E 's/-v[0-9].*(\.zip)$/\1/')

                # Create symlink:
                # Target: ../<version_tag>/<filename> (relative path)
                # Link Name: latest/<clean_name>
                ln -sf "../$latest_tag/$filename" "$latest_link_dir/$link_name"
                echo "Symlinked: latest/$link_name -> $latest_tag/$filename"
            fi
        done
    fi

done

echo "------------------------------------------------"
echo "Update process finished."
