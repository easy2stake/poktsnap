#!/usr/bin/env bash

# Retention cleanup script for snapshot files on Stratos
# This script automatically deletes old snapshots based on retention policies

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared RPC utilities
source "$SCRIPT_DIR/rpc-utils.sh"

SCRIPT_NAME="cleanup-old-snapshots"

log "$SCRIPT_NAME" "Starting retention cleanup..."

# Configuration - can be overridden by environment variables
SNAP_DATA_PATTERN="${SNAP_DATA_PATTERN:-pocket-snap-data}"
ARCHIVE_DATA_PATTERN="${ARCHIVE_DATA_PATTERN:-pocket-archive-data}"
SNAP_DATA_RETENTION="${SNAP_DATA_RETENTION:-5}"
ARCHIVE_DATA_RETENTION="${ARCHIVE_DATA_RETENTION:-3}"

log "$SCRIPT_NAME" "Configuration:"
log "$SCRIPT_NAME" "  SNAP_DATA_PATTERN: $SNAP_DATA_PATTERN"
log "$SCRIPT_NAME" "  SNAP_DATA_RETENTION: $SNAP_DATA_RETENTION"
log "$SCRIPT_NAME" "  ARCHIVE_DATA_PATTERN: $ARCHIVE_DATA_PATTERN"
log "$SCRIPT_NAME" "  ARCHIVE_DATA_RETENTION: $ARCHIVE_DATA_RETENTION"

# Check if required environment variables are set
validate_rpc_env "$SCRIPT_NAME"

# Get list of already uploaded files from Stratos
UPLOADED_FILES=$(rpc_list "$SCRIPT_NAME")

# Parse the file list and separate into snap-data and archive-data
# File list format: filename filehash filesize createtime
# We need to filter lines that have all 4 columns and contain .tar

# Create temporary files to store sorted lists
SNAP_DATA_LIST=$(mktemp)
ARCHIVE_DATA_LIST=$(mktemp)

# Clean up temp files on exit
trap "rm -f $SNAP_DATA_LIST $ARCHIVE_DATA_LIST" EXIT

# Parse and categorize files
echo "$UPLOADED_FILES" | grep ".tar" | awk 'NF>=4 {print $0}' | while read -r line; do
    FILENAME=$(echo "$line" | awk '{print $1}')
    FILEHASH=$(echo "$line" | awk '{print $2}')
    FILESIZE=$(echo "$line" | awk '{print $3}')
    CREATETIME=$(echo "$line" | awk '{print $4}')
    
    # Check if filename matches snap-data pattern
    if echo "$FILENAME" | grep -q "$SNAP_DATA_PATTERN"; then
        echo "$CREATETIME $FILENAME $FILEHASH" >> "$SNAP_DATA_LIST"
    fi
    
    # Check if filename matches archive-data pattern
    if echo "$FILENAME" | grep -q "$ARCHIVE_DATA_PATTERN"; then
        echo "$CREATETIME $FILENAME $FILEHASH" >> "$ARCHIVE_DATA_LIST"
    fi
done

# Sort files by timestamp (oldest first)
if [ -f "$SNAP_DATA_LIST" ]; then
    sort -n -o "$SNAP_DATA_LIST" "$SNAP_DATA_LIST"
fi

if [ -f "$ARCHIVE_DATA_LIST" ]; then
    sort -n -o "$ARCHIVE_DATA_LIST" "$ARCHIVE_DATA_LIST"
fi

# Count files
SNAP_DATA_COUNT=$(wc -l < "$SNAP_DATA_LIST" | tr -d ' ')
ARCHIVE_DATA_COUNT=$(wc -l < "$ARCHIVE_DATA_LIST" | tr -d ' ')

log "$SCRIPT_NAME" "Found $SNAP_DATA_COUNT snap-data files (retention: $SNAP_DATA_RETENTION)"
log "$SCRIPT_NAME" "Found $ARCHIVE_DATA_COUNT archive-data files (retention: $ARCHIVE_DATA_RETENTION)"

# Function to delete old files
delete_old_files() {
    local FILE_LIST="$1"
    local RETENTION="$2"
    local FILE_TYPE="$3"
    local FILE_COUNT="$4"
    
    if [ "$FILE_COUNT" -le "$RETENTION" ]; then
        log "$SCRIPT_NAME" "No cleanup needed for $FILE_TYPE files (count: $FILE_COUNT, retention: $RETENTION)"
        return 0
    fi
    
    local FILES_TO_DELETE=$((FILE_COUNT - RETENTION))
    log "$SCRIPT_NAME" "Need to delete $FILES_TO_DELETE old $FILE_TYPE file(s)"
    
    local DELETED=0
    while IFS= read -r line && [ $DELETED -lt $FILES_TO_DELETE ]; do
        CREATETIME=$(echo "$line" | awk '{print $1}')
        FILENAME=$(echo "$line" | awk '{print $2}')
        FILEHASH=$(echo "$line" | awk '{print $3}')
        
        log "$SCRIPT_NAME" "  ↳ Deleting: $FILENAME (hash: $FILEHASH, timestamp: $CREATETIME)"
        
        # Delete the file
        DELETE_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" delete "$FILEHASH" 2>&1)
        
        # Check if delete was successful
        if echo "$DELETE_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
            log "$SCRIPT_NAME" "  ↳ SUCCESS: $FILENAME deleted successfully"
            DELETED=$((DELETED + 1))
        else
            log "$SCRIPT_NAME" "  ↳ ERROR: Failed to delete $FILENAME"
            log "$SCRIPT_NAME" "  ↳ Output: $DELETE_OUTPUT"
        fi
        
        log "$SCRIPT_NAME" ""
    done < "$FILE_LIST"
    
    log "$SCRIPT_NAME" "Deleted $DELETED $FILE_TYPE file(s)"
}

# Delete old snap-data files if needed
if [ "$SNAP_DATA_COUNT" -gt 0 ]; then
    delete_old_files "$SNAP_DATA_LIST" "$SNAP_DATA_RETENTION" "snap-data" "$SNAP_DATA_COUNT"
fi

# Delete old archive-data files if needed
if [ "$ARCHIVE_DATA_COUNT" -gt 0 ]; then
    delete_old_files "$ARCHIVE_DATA_LIST" "$ARCHIVE_DATA_RETENTION" "archive-data" "$ARCHIVE_DATA_COUNT"
fi

log "$SCRIPT_NAME" "Retention cleanup completed"

