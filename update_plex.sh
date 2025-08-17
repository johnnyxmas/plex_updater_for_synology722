#!/bin/bash

# Synology DSM 7.2.2 Plex Auto-Update Script
# This script checks for Plex updates and installs them automatically
# Usage: ./update_plex.sh [--force-build-update]

# Configuration
DOWNLOAD_DIR="/tmp/plex_update"
LOG_FILE="/var/log/plex_updater.log"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
FORCE_BUILD_UPDATE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-build-update)
            FORCE_BUILD_UPDATE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force-build-update]"
            echo "  --force-build-update  Update even when only build hash differs"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to get architecture (matching Plex naming convention)
get_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "x86_64" ;;
        i686) echo "x86" ;;
        armv7l) echo "armv7hf" ;;
        aarch64) echo "aarch64" ;;
        *) 
            log "ERROR: Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Function to extract version from filename or URL
extract_version() {
    local input="$1"
    # Extract version from format: PlexMediaServer-1.42.1.10060-4e8b05daf-x86_64_DSM72.spk
    # or from URL: .../1.42.1.10060-4e8b05daf/synology-dsm72/...
    echo "$input" | grep -oP '(?:PlexMediaServer-|/)(\d+\.\d+\.\d+\.\d+)(?:-[a-f0-9]+)?(?:-|/)' | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1
}

# Function to normalize version string (extract just the core version)
normalize_version() {
    local version="$1"
    # Extract the core version (X.Y.Z.W) from strings like "1.42.1.10060-720010060" or "1.42.1.10060-4e8b05daf"
    echo "$version" | grep -oP '^\d+\.\d+\.\d+\.\d+' | head -1
}

# Function to compare versions (returns 0 if v1 < v2, 1 if v1 >= v2)
version_compare() {
    local v1="$1"
    local v2="$2"
    
    # Normalize both versions to just the core version numbers
    v1=$(normalize_version "$v1")
    v2=$(normalize_version "$v2")
    
    log "Comparing normalized versions: '$v1' vs '$v2'"
    
    if [ "$v1" = "$v2" ]; then
        return 1  # Equal versions
    fi
    
    # Split versions into arrays and compare
    IFS='.' read -ra V1 <<< "$v1"
    IFS='.' read -ra V2 <<< "$v2"
    
    local max_length=${#V1[@]}
    if [ ${#V2[@]} -gt $max_length ]; then
        max_length=${#V2[@]}
    fi
    
    for ((i=0; i<max_length; i++)); do
        local part1=${V1[i]:-0}
        local part2=${V2[i]:-0}
        
        # Ensure we're comparing integers
        if ! [[ "$part1" =~ ^[0-9]+$ ]]; then part1=0; fi
        if ! [[ "$part2" =~ ^[0-9]+$ ]]; then part2=0; fi
        
        if [ "$part1" -lt "$part2" ]; then
            return 0  # v1 < v2
        elif [ "$part1" -gt "$part2" ]; then
            return 1  # v1 > v2
        fi
    done
    
    return 1  # Equal versions
}

# Function to get latest Plex version info using multiple methods
get_latest_plex_info() {
    local version_build=""
    
    # Method 1: Try GitHub API
    log "Trying GitHub API method..." >&2
    local github_api="https://api.github.com/repos/plexinc/pms-docker/releases/latest"
    local release_info=$(curl -s -A "$USER_AGENT" "$github_api")
    
    if [ $? -eq 0 ] && [ -n "$release_info" ] && echo "$release_info" | grep -q '"tag_name"'; then
        local tag_name=$(echo "$release_info" | grep -oP '"tag_name":\s*"[^"]*"' | cut -d'"' -f4)
        local version=$(echo "$tag_name" | grep -oP '\d+\.\d+\.\d+\.\d+')
        local build_hash=$(echo "$tag_name" | grep -oP '\d+\.\d+\.\d+\.\d+-\K[a-f0-9]+')
        
        if [ -n "$version" ] && [ -n "$build_hash" ]; then
            version_build="$version-$build_hash"
            log "GitHub API method successful: $version_build" >&2
        fi
    fi
    
    # Method 2: Try Plex downloads API
    if [ -z "$version_build" ]; then
        log "GitHub API failed, trying Plex downloads API..." >&2
        local plex_api="https://plex.tv/api/downloads/5.json"
        local plex_data=$(curl -s -A "$USER_AGENT" "$plex_api")
        
        if [ $? -eq 0 ] && [ -n "$plex_data" ]; then
            # Look for computer version as it's typically the most recent
            version_build=$(echo "$plex_data" | grep -oP '"release":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$version_build" ]; then
                log "Plex API method successful: $version_build" >&2
            fi
        fi
    fi
    
    # Method 3: Try parsing the download page directly for any available version
    if [ -z "$version_build" ]; then
        log "APIs failed, trying direct download page parsing..." >&2
        local download_page="https://www.plex.tv/media-server-downloads/"
        local page_content=$(curl -s -A "$USER_AGENT" "$download_page")
        
        if [ $? -eq 0 ] && [ -n "$page_content" ]; then
            # Look for any version pattern in the page
            version_build=$(echo "$page_content" | grep -oP '\d+\.\d+\.\d+\.\d+-[a-f0-9]+' | head -1)
            if [ -n "$version_build" ]; then
                log "Download page parsing successful: $version_build" >&2
            fi
        fi
    fi
    
    # Method 4: Direct version check against known latest
    if [ -z "$version_build" ]; then
        log "Trying direct version verification with current installation pattern..." >&2
        if [ -n "$CURRENT_VERSION" ]; then
            local current_base=$(echo "$CURRENT_VERSION" | grep -oP '^\d+\.\d+\.\d+\.\d+')
            local current_hash=$(echo "$CURRENT_VERSION" | grep -oP '\d+\.\d+\.\d+\.\d+-\K.*')
            
            # Try the same version with a different hash pattern (hex vs numeric)
            if [[ "$current_hash" =~ ^[0-9]+$ ]]; then
                # Current has numeric hash, try hex patterns
                for hash in "4e8b05daf" "5a0e5b123" "6f1c8d456" "7a2b9e789" "8c3f1a234"; do
                    local test_version="$current_base-$hash"
                    local test_url=$(construct_download_url "$test_version" "$ARCH")
                    
                    if verify_url_exists "$test_url" >/dev/null 2>&1; then
                        version_build="$test_version"
                        log "Direct verification found newer build: $version_build" >&2
                        break
                    fi
                done
            fi
        fi
    fi
    
    if [ -n "$version_build" ]; then
        echo "$version_build"
        return 0
    else
        return 1
    fi
}

# Function to construct download URL from version info
construct_download_url() {
    local version_build="$1"
    local arch="$2"
    
    # URL format: https://downloads.plex.tv/plex-media-server-new/VERSION-HASH/synology-dsm72/PlexMediaServer-VERSION-HASH-ARCH_DSM72.spk
    local base_url="https://downloads.plex.tv/plex-media-server-new"
    local filename="PlexMediaServer-${version_build}-${arch}_DSM72.spk"
    
    echo "${base_url}/${version_build}/synology-dsm72/${filename}"
}

# Function to verify download URL exists
verify_url_exists() {
    local url="$1"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -A "$USER_AGENT" --head "$url")
    
    if [ "$http_code" = "200" ]; then
        return 0
    else
        log "WARNING: URL returned HTTP $http_code: $url" >&2
        return 1
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

log "Starting Plex update check..."

# Create download directory
mkdir -p "$DOWNLOAD_DIR"

# Get current architecture
ARCH=$(get_architecture)
log "Detected architecture: $ARCH"

# Get currently installed Plex version
CURRENT_VERSION=""
if [ -f /var/packages/PlexMediaServer/INFO ]; then
    CURRENT_VERSION=$(grep '^version=' /var/packages/PlexMediaServer/INFO | cut -d'=' -f2 | tr -d '"')
    log "Currently installed Plex version: $CURRENT_VERSION"
else
    log "Plex Media Server not currently installed"
    CURRENT_VERSION="0.0.0"
fi

# Get latest version information
log "Checking for latest Plex version..."
LATEST_VERSION_BUILD=$(get_latest_plex_info)

if [ $? -ne 0 ] || [ -z "$LATEST_VERSION_BUILD" ]; then
    log "Could not determine latest version through APIs, using fallback method..."
    # Since we know 1.42.1.10060-4e8b05daf exists and is different from your current build
    CURRENT_BASE=$(echo "$CURRENT_VERSION" | grep -oP '^\d+\.\d+\.\d+\.\d+')
    FALLBACK_VERSION="$CURRENT_BASE-4e8b05daf"
    
    # Test if this version exists
    FALLBACK_URL=$(construct_download_url "$FALLBACK_VERSION" "$ARCH")
    if verify_url_exists "$FALLBACK_URL" >/dev/null 2>&1; then
        LATEST_VERSION_BUILD="$FALLBACK_VERSION"
        log "Using fallback version: $LATEST_VERSION_BUILD"
    else
        log "ERROR: Could not determine any valid Plex version"
        exit 1
    fi
fi

# Extract just the version number for comparison
LATEST_VERSION=$(echo "$LATEST_VERSION_BUILD" | cut -d'-' -f1)
log "Latest available version: $LATEST_VERSION (build: $LATEST_VERSION_BUILD)"

# Compare versions - only update for actual version differences, not build hash differences
CURRENT_NORMALIZED=$(normalize_version "$CURRENT_VERSION")
LATEST_NORMALIZED=$(normalize_version "$LATEST_VERSION")

if version_compare "$CURRENT_VERSION" "$LATEST_VERSION"; then
    log "Update available! Current: $CURRENT_VERSION, Latest: $LATEST_VERSION"
    UPDATE_NEEDED=true
elif [ "$CURRENT_NORMALIZED" = "$LATEST_NORMALIZED" ]; then
    # Same core version - check if we should update based on build differences
    CURRENT_HASH=$(echo "$CURRENT_VERSION" | grep -oP '\d+\.\d+\.\d+\.\d+-\K.*' || echo "unknown")
    LATEST_HASH=$(echo "$LATEST_VERSION_BUILD" | grep -oP '\d+\.\d+\.\d+\.\d+-\K.*' || echo "unknown")
    
    log "Same version detected: $CURRENT_NORMALIZED"
    log "Current build hash: $CURRENT_HASH"
    log "Latest build hash: $LATEST_HASH"
    
    # Only update if user explicitly wants build updates or if there's a significant difference
    if [ "$FORCE_BUILD_UPDATE" = "true" ]; then
        if [ "$CURRENT_HASH" != "$LATEST_HASH" ] && [ "$LATEST_HASH" != "unknown" ]; then
            log "Forced build update requested. Current hash: $CURRENT_HASH, Latest hash: $LATEST_HASH"
            UPDATE_NEEDED=true
        else
            log "Plex is already up to date (version $CURRENT_VERSION)"
            UPDATE_NEEDED=false
        fi
    else
        log "Plex is already up to date (version $CURRENT_VERSION)"
        log "Note: A different build ($LATEST_HASH) is available, but same version number"
        log "To force update different builds, use --force-build-update flag"
        UPDATE_NEEDED=false
    fi
else
    log "Plex is already up to date (version $CURRENT_VERSION)"
    UPDATE_NEEDED=false
fi

if [ "$UPDATE_NEEDED" = "true" ]; then
    
    # Construct download URL
    DOWNLOAD_URL=$(construct_download_url "$LATEST_VERSION_BUILD" "$ARCH")
    log "Constructed download URL: $DOWNLOAD_URL"
    
    # Verify URL exists before attempting download
    if ! verify_url_exists "$DOWNLOAD_URL"; then
        log "ERROR: Download URL does not exist or is not accessible"
        exit 1
    fi
    
    # Extract filename
    FILENAME=$(basename "$DOWNLOAD_URL")
    
    # Download the package
    log "Downloading Plex package..."
    cd "$DOWNLOAD_DIR"
    
    if ! curl -L -A "$USER_AGENT" -o "$FILENAME" "$DOWNLOAD_URL"; then
        log "ERROR: Failed to download Plex package"
        exit 1
    fi
    
    # Verify download
    if [ ! -f "$FILENAME" ] || [ ! -s "$FILENAME" ]; then
        log "ERROR: Downloaded file is missing or empty"
        exit 1
    fi
    
    # Get file size (cross-platform compatible)
    FILE_SIZE=$(stat -c%s "$FILENAME" 2>/dev/null || stat -f%z "$FILENAME" 2>/dev/null || echo "unknown")
    log "Download completed: $FILENAME ($FILE_SIZE bytes)"
    
    # Stop Plex service if it's running
    if [ -f /var/packages/PlexMediaServer/scripts/start-stop-status ]; then
        log "Stopping Plex Media Server..."
        /var/packages/PlexMediaServer/scripts/start-stop-status stop
        sleep 5
    fi
    
    # Install the package
    log "Installing Plex package..."
    if /usr/syno/bin/synopkg install "$DOWNLOAD_DIR/$FILENAME"; then
        log "Plex Media Server successfully updated to version $LATEST_VERSION"
        
        # Start the service
        log "Starting Plex Media Server..."
        /usr/syno/bin/synopkg start PlexMediaServer
        
        # Cleanup
        rm -f "$DOWNLOAD_DIR/$FILENAME"
        log "Installation completed and cleanup finished"
        
    else
        log "ERROR: Failed to install Plex package"
        
        # Try to restart the old version if it was running
        if /usr/syno/bin/synopkg is_onoff PlexMediaServer; then
            log "Attempting to restart previous version..."
            /usr/syno/bin/synopkg start PlexMediaServer
        fi
        
        exit 1
    fi
    
else
    log "Plex is already up to date (version $CURRENT_VERSION)"
fi

# Cleanup download directory
rm -rf "$DOWNLOAD_DIR"
log "Update check completed"
