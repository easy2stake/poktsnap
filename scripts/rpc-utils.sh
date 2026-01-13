#!/usr/bin/env bash

# Shared utilities for RPC client operations
# This script provides common functions for interacting with Stratos via rpcclient

# Configuration
MAX_RETRIES=5
RETRY_DELAY=10

# Logging function
# Usage: log "script-name" "message"
log() {
    local SCRIPT_NAME="$1"
    local MESSAGE="$2"
    echo "[$SCRIPT_NAME] [$(date '+%Y-%m-%d %H:%M:%S')] $MESSAGE"
}

# Validate required RPC environment variables
# Exits with error if RPC_URL is not set
# RPC_PASSWORD can be empty (default for SDS)
validate_rpc_env() {
    local SCRIPT_NAME="${1:-rpc-utils}"
    
    if [ -z "$RPC_URL" ]; then
        log "$SCRIPT_NAME" "ERROR: RPC_URL not set"
        exit 1
    fi
}

# Fetch list of files from Stratos with retry logic
# Returns file list via stdout
# Exits on failure after MAX_RETRIES attempts
# Usage: UPLOADED_FILES=$(rpc_list "script-name")
rpc_list() {
    local SCRIPT_NAME="${1:-rpc-utils}"
    
    log "$SCRIPT_NAME" "Fetching list of uploaded files from Stratos..."
    
    local UPLOADED_FILES
    UPLOADED_FILES=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)
    local EXIT_CODE=$?
    
    local RETRY_COUNT=0
    while [ $EXIT_CODE -ne 0 ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        log "$SCRIPT_NAME" "ERROR: Failed to fetch uploaded file list. Output: $UPLOADED_FILES"
        RETRY_COUNT=$((RETRY_COUNT+1))
        log "$SCRIPT_NAME" "Retrying ($RETRY_COUNT/$MAX_RETRIES) in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        UPLOADED_FILES=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)
        EXIT_CODE=$?
    done
    
    if [ $EXIT_CODE -ne 0 ]; then
        log "$SCRIPT_NAME" "ERROR: Failed to fetch uploaded file list after $MAX_RETRIES retries. Output: $UPLOADED_FILES"
        exit 1
    fi
    
    log "$SCRIPT_NAME" "Successfully fetched file list from Stratos"
    
    # Return the file list
    echo "$UPLOADED_FILES"
}

# Split and upload large file
# Usage: split_and_upload_file "script-name" "filepath" "max_chunk_size_bytes"
# Returns: 0 on success, 1 on failure
split_and_upload_file() {
    local SCRIPT_NAME="$1"
    local FILEPATH="$2"
    local MAX_CHUNK_SIZE="$3"
    local FILENAME=$(basename "$FILEPATH")
    local FILEDIR=$(dirname "$FILEPATH")
    local CHUNK_PREFIX="${FILEDIR}/${FILENAME}.part"
    
    log "$SCRIPT_NAME" "Splitting large file: $FILENAME"
    
    # Split the file into chunks
    if ! split -b "$MAX_CHUNK_SIZE" "$FILEPATH" "$CHUNK_PREFIX"; then
        log "$SCRIPT_NAME" "ERROR: Failed to split file $FILENAME"
        return 1
    fi
    
    # Find all chunk files
    local CHUNK_FILES=$(ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
    local CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
    local CHUNK_HASHES=""
    local UPLOADED_CHUNKS=0
    
    log "$SCRIPT_NAME" "Created $CHUNK_COUNT chunk(s) for $FILENAME"
    
    # Upload each chunk
    local CHUNK_NUM=1
    echo "$CHUNK_FILES" | while IFS= read -r CHUNK_FILE; do
        local CHUNK_NAME=$(basename "$CHUNK_FILE")
        log "$SCRIPT_NAME" "  ↳ Uploading chunk $CHUNK_NUM/$CHUNK_COUNT: $CHUNK_NAME"
        
        local UPLOAD_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$CHUNK_FILE" 2>&1)
        
        if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
            local CHUNK_HASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
            if [ -n "$CHUNK_HASH" ]; then
                CHUNK_HASHES="${CHUNK_HASHES}${CHUNK_NAME}:${CHUNK_HASH}\n"
                log "$SCRIPT_NAME" "  ↳ SUCCESS: $CHUNK_NAME uploaded (hash: $CHUNK_HASH)"
                UPLOADED_CHUNKS=$((UPLOADED_CHUNKS + 1))
            fi
        else
            log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload chunk $CHUNK_NAME"
            log "$SCRIPT_NAME" "  ↳ Output: $UPLOAD_OUTPUT"
            # Cleanup chunks on failure
            rm -f "${CHUNK_PREFIX}"*
            return 1
        fi
        
        CHUNK_NUM=$((CHUNK_NUM + 1))
    done
    
    # Create manifest file
    local MANIFEST_FILE="${FILEDIR}/${FILENAME}.manifest"
    local FILE_SIZE=$(stat -c%s "$FILEPATH" 2>/dev/null || echo "0")
    
    cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_CHUNK_SIZE,
  "chunks": [
$(echo -e "$CHUNK_HASHES" | sed 's/\(.*\):\(.*\)/    {"filename": "\1", "hash": "\2"},/' | sed '$ s/,$//')
  ]
}
EOF
    
    # Upload manifest file
    log "$SCRIPT_NAME" "Uploading manifest file: ${FILENAME}.manifest"
    local MANIFEST_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$MANIFEST_FILE" 2>&1)
    
    if echo "$MANIFEST_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        local MANIFEST_HASH=$(echo "$MANIFEST_OUTPUT" | grep "File " | awk '{print $3}')
        log "$SCRIPT_NAME" "  ↳ SUCCESS: Manifest uploaded (hash: $MANIFEST_HASH)"
        
        # Cleanup local chunks and manifest
        rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
        
        log "$SCRIPT_NAME" "  ↳ All $CHUNK_COUNT chunk(s) and manifest uploaded successfully"
        return 0
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload manifest file"
        log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
        # Cleanup chunks on failure
        rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
        return 1
    fi
}
