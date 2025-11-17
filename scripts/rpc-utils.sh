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

