#!/usr/bin/env bash

# Auto-upload monitoring script for snapshot files
# This script runs via cron to automatically upload new snapshots to Stratos

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting snapshot upload monitor..."

# Check if required environment variables are set
# RPC_PASSWORD can be empty (default for SDS)
if [ -z "$RPC_URL" ]; then
    log "ERROR: RPC_URL not set"
    exit 1
fi

# Configuration
ARCHIVE_DIR="/archive"
MAX_RETRIES=5
RETRY_DELAY=10

if [ ! -d "$ARCHIVE_DIR" ]; then
    log "ERROR: Archive directory $ARCHIVE_DIR does not exist"
    exit 1
fi

# Get list of already uploaded files from Stratos
log "Fetching list of already uploaded files..."
UPLOADED_FILES=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)

RETRY_COUNT=0
while [ $? -ne 0 ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    log "ERROR: Failed to fetch uploaded file list. Output: $UPLOADED_FILES"
    RETRY_COUNT=$((RETRY_COUNT+1))
    log "Retrying ($RETRY_COUNT/$MAX_RETRIES) in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    UPLOADED_FILES=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)
done

if [ $? -ne 0 ]; then
    log "ERROR: Failed to fetch uploaded file list after $MAX_RETRIES retries. Output: $UPLOADED_FILES"
    exit 1
fi

# Find all snapshot files older than 15 minutes
# This ensures the file is complete and not being written to
log "Scanning for snapshot files older than 15 minutes..."

find "$ARCHIVE_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tar.zstd" \) -mmin +15 2>/dev/null | while read -r FILEPATH; do
    FILENAME=$(basename "$FILEPATH")
    
    log "Found file: $FILENAME"
    
    # Check if file is already uploaded
    if echo "$UPLOADED_FILES" | grep -q "^$FILENAME "; then
        log "  ↳ SKIP: $FILENAME already uploaded to Stratos"
        continue
    fi
    
    log "  ↳ Uploading: $FILENAME"
    
    # Upload the file
    UPLOAD_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1)
    
    # Check if upload was successful
    if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        log "  ↳ SUCCESS: $FILENAME uploaded successfully"
        
        # Extract and log the file hash if available
        FILEHASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$FILEHASH" ]; then
            log "  ↳ File hash: $FILEHASH"
        fi
    else
        log "  ↳ ERROR: Upload failed for $FILENAME"
        log "  ↳ Output: $UPLOAD_OUTPUT"
    fi
    
    log ""
done

log "Snapshot upload monitor completed"

