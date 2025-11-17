#!/usr/bin/env bash

# Auto-upload monitoring script for snapshot files
# This script runs via cron to automatically upload new snapshots to Stratos

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared RPC utilities
source "$SCRIPT_DIR/rpc-utils.sh"

SCRIPT_NAME="monitor-and-upload"

log "$SCRIPT_NAME" "Starting snapshot upload monitor..."

# Check if required environment variables are set
validate_rpc_env "$SCRIPT_NAME"

# Configuration
ARCHIVE_DIR="/archive"

if [ ! -d "$ARCHIVE_DIR" ]; then
    log "$SCRIPT_NAME" "ERROR: Archive directory $ARCHIVE_DIR does not exist"
    exit 1
fi

# Get list of already uploaded files from Stratos
UPLOADED_FILES=$(rpc_list "$SCRIPT_NAME")

# Find all snapshot files older than 15 minutes
# This ensures the file is complete and not being written to
log "$SCRIPT_NAME" "Scanning for snapshot files older than 15 minutes..."

find "$ARCHIVE_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tar.zstd" \) -mmin +15 2>/dev/null | while read -r FILEPATH; do
    FILENAME=$(basename "$FILEPATH")
    
    log "$SCRIPT_NAME" "Found file: $FILENAME"
    
    # Check if file is already uploaded
    if echo "$UPLOADED_FILES" | grep -q "^$FILENAME "; then
        log "$SCRIPT_NAME" "  ↳ SKIP: $FILENAME already uploaded to Stratos"
        continue
    fi
    
    log "$SCRIPT_NAME" "  ↳ Uploading: $FILENAME"
    
    # Upload the file
    UPLOAD_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1)
    
    # Check if upload was successful
    if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        log "$SCRIPT_NAME" "  ↳ SUCCESS: $FILENAME uploaded successfully"
        
        # Extract and log the file hash if available
        FILEHASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$FILEHASH" ]; then
            log "$SCRIPT_NAME" "  ↳ File hash: $FILEHASH"
        fi
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Upload failed for $FILENAME"
        log "$SCRIPT_NAME" "  ↳ Output: $UPLOAD_OUTPUT"
    fi
    
    log "$SCRIPT_NAME" ""
done

log "$SCRIPT_NAME" "Snapshot upload monitor completed"

