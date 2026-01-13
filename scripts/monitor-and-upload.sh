#!/usr/bin/env bash

# Auto-upload monitoring script for snapshot files
# This script runs via cron to automatically upload new snapshots to Stratos

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared RPC utilities
source "$SCRIPT_DIR/rpc-utils.sh"

SCRIPT_NAME="monitor-and-upload"

# Configuration - read from environment variables with defaults
ARCHIVE_DIR="${CONTAINER_ARCHIVE_DIR:-/archive}"
MAX_FILE_SIZE_GB="${MAX_FILE_SIZE_GB:-10}"
MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_GB * 1024 * 1024 * 1024))
LOCKFILE="/tmp/monitor-and-upload.lock"

# Feature flags - read from environment variables with defaults
# Convert to lowercase for case-insensitive comparison
PROCESS_LARGE_FILES="${PROCESS_LARGE_FILES:-true}"
PROCESS_LARGE_FILES=$(echo "$PROCESS_LARGE_FILES" | tr '[:upper:]' '[:lower:]')

PROCESS_ORPHANED_CHUNKS="${PROCESS_ORPHANED_CHUNKS:-true}"
PROCESS_ORPHANED_CHUNKS=$(echo "$PROCESS_ORPHANED_CHUNKS" | tr '[:upper:]' '[:lower:]')

# Global variables set during execution
UPLOADED_FILES=""

# ============================================================================
# LOCK MANAGEMENT
# ============================================================================

acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        if kill -0 $(cat "$LOCKFILE" 2>/dev/null) 2>/dev/null; then
            log "$SCRIPT_NAME" "Another instance is already running (PID: $(cat "$LOCKFILE")). Exiting."
            exit 0
        else
            log "$SCRIPT_NAME" "Stale lockfile found, removing..."
            rm -f "$LOCKFILE"
        fi
    fi
    
    echo $$ > "$LOCKFILE"
    trap "rm -f $LOCKFILE" EXIT INT TERM
}

# ============================================================================
# MANIFEST OPERATIONS
# ============================================================================

# Create initial manifest after split (proof of complete split)
# Args: $1=manifest_file, $2=filename, $3=file_size, $4=chunk_count, $5=chunk_files
create_initial_manifest() {
    local MANIFEST_FILE="$1"
    local FILENAME="$2"
    local FILE_SIZE="$3"
    local CHUNK_COUNT="$4"
    local CHUNK_FILES="$5"
    local ORPHANED="${6:-false}"
    
    local MANIFEST_CHUNK_LIST=""
    while IFS= read -r CHUNK_FILE; do
        [ -z "$CHUNK_FILE" ] && continue
        local CHUNK_NAME=$(basename "$CHUNK_FILE")
        if [ -n "$MANIFEST_CHUNK_LIST" ]; then
            MANIFEST_CHUNK_LIST="${MANIFEST_CHUNK_LIST},\n"
        fi
        MANIFEST_CHUNK_LIST="${MANIFEST_CHUNK_LIST}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": null}"
    done <<< "$CHUNK_FILES"
    
    if [ "$ORPHANED" = true ]; then
        cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_FILE_SIZE_BYTES,
  "split_complete": true,
  "upload_complete": false,
  "orphaned": true,
  "chunks": [
$(echo -e "$MANIFEST_CHUNK_LIST")
  ]
}
EOF
    else
        cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_FILE_SIZE_BYTES,
  "split_complete": true,
  "upload_complete": false,
  "chunks": [
$(echo -e "$MANIFEST_CHUNK_LIST")
  ]
}
EOF
    fi
    
    log "$SCRIPT_NAME" "  ↳ Created local manifest: ${FILENAME}.manifest (proof of split completion)"
}

# Create final manifest with hashes after successful upload
# Args: $1=manifest_file, $2=filename, $3=file_size, $4=chunk_count, $5=manifest_content, $6=orphaned
create_final_manifest() {
    local MANIFEST_FILE="$1"
    local FILENAME="$2"
    local FILE_SIZE="$3"
    local CHUNK_COUNT="$4"
    local MANIFEST_CONTENT="$5"
    local ORPHANED="${6:-false}"
    
    if [ "$ORPHANED" = true ]; then
        cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_FILE_SIZE_BYTES,
  "split_complete": true,
  "upload_complete": true,
  "orphaned": true,
  "chunks": [
$(echo -e "$MANIFEST_CONTENT")
  ]
}
EOF
    else
        cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_FILE_SIZE_BYTES,
  "split_complete": true,
  "upload_complete": true,
  "chunks": [
$(echo -e "$MANIFEST_CONTENT")
  ]
}
EOF
    fi
}

# Upload manifest file to Stratos
# Args: $1=manifest_file, $2=chunk_prefix, $3=chunk_count
# Returns: 0 on success, 1 on failure
upload_manifest() {
    local MANIFEST_FILE="$1"
    local CHUNK_PREFIX="$2"
    local CHUNK_COUNT="$3"
    local MANIFEST_NAME=$(basename "$MANIFEST_FILE")
    
    log "$SCRIPT_NAME" "  ↳ Uploading manifest file: $MANIFEST_NAME"
    local MANIFEST_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$MANIFEST_FILE" 2>&1)
    
    if echo "$MANIFEST_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        local MANIFEST_HASH=$(echo "$MANIFEST_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$MANIFEST_HASH" ]; then
            log "$SCRIPT_NAME" "  ↳ SUCCESS: All $CHUNK_COUNT chunk(s) and manifest uploaded (manifest hash: $MANIFEST_HASH)"
        else
            log "$SCRIPT_NAME" "  ↳ WARNING: Manifest uploaded but hash extraction failed"
            log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
        fi
        # Cleanup local chunks and manifest (keep tmp directory)
        rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
        return 0
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload manifest file"
        log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
        return 1
    fi
}

# ============================================================================
# CHUNK OPERATIONS
# ============================================================================

# Split a large file into chunks
# Args: $1=filepath, $2=chunk_prefix
# Returns: 0 on success, 1 on failure
split_file() {
    local FILEPATH="$1"
    local CHUNK_PREFIX="$2"
    
    log "$SCRIPT_NAME" "  ↳ Splitting file into chunks..."
    if ! split -b "$MAX_FILE_SIZE_BYTES" "$FILEPATH" "$CHUNK_PREFIX"; then
        log "$SCRIPT_NAME" "  ↳ ERROR: Failed to split file $(basename "$FILEPATH")"
        return 1
    fi
    return 0
}

# Upload chunks and build manifest content
# Args: $1=chunk_files (newline separated), $2=is_orphaned
# Sets: MANIFEST_CONTENT (global), UPLOAD_SUCCESS (global)
upload_chunks() {
    local CHUNK_FILES="$1"
    local IS_ORPHANED="${2:-false}"
    local CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
    
    MANIFEST_CONTENT=""
    UPLOAD_SUCCESS=true
    
    local CHUNK_NUM=1
    while IFS= read -r CHUNK_FILE; do
        [ -z "$CHUNK_FILE" ] && continue
        local CHUNK_NAME=$(basename "$CHUNK_FILE")
        local PREFIX_TEXT=""
        [ "$IS_ORPHANED" = true ] && PREFIX_TEXT="orphaned "
        
        # Check if chunk is already uploaded
        if echo "$UPLOADED_FILES" | grep -q "^${CHUNK_NAME} "; then
            log "$SCRIPT_NAME" "    ↳ SKIP: $CHUNK_NAME already uploaded"
            # Get hash from uploaded files list for manifest
            local CHUNK_HASH=$(echo "$UPLOADED_FILES" | grep "^${CHUNK_NAME} " | awk '{print $2}')
            if [ -n "$CHUNK_HASH" ]; then
                if [ -n "$MANIFEST_CONTENT" ]; then
                    MANIFEST_CONTENT="${MANIFEST_CONTENT},\n"
                fi
                MANIFEST_CONTENT="${MANIFEST_CONTENT}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": \"${CHUNK_HASH}\"}"
            else
                log "$SCRIPT_NAME" "    ↳ WARNING: $CHUNK_NAME found in uploaded files but hash extraction failed"
                UPLOAD_SUCCESS=false
                break
            fi
        else
            log "$SCRIPT_NAME" "    ↳ Uploading ${PREFIX_TEXT}chunk $CHUNK_NUM/$CHUNK_COUNT: $CHUNK_NAME"
            
            local CHUNK_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$CHUNK_FILE" 2>&1)
            
            if echo "$CHUNK_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
                local CHUNK_HASH=$(echo "$CHUNK_OUTPUT" | grep "File " | awk '{print $3}')
                if [ -n "$CHUNK_HASH" ]; then
                    if [ -n "$MANIFEST_CONTENT" ]; then
                        MANIFEST_CONTENT="${MANIFEST_CONTENT},\n"
                    fi
                    MANIFEST_CONTENT="${MANIFEST_CONTENT}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": \"${CHUNK_HASH}\"}"
                    log "$SCRIPT_NAME" "    ↳ SUCCESS: $CHUNK_NAME uploaded (hash: $CHUNK_HASH)"
                else
                    log "$SCRIPT_NAME" "    ↳ WARNING: $CHUNK_NAME uploaded but hash extraction failed"
                    log "$SCRIPT_NAME" "    ↳ Output: $CHUNK_OUTPUT"
                    UPLOAD_SUCCESS=false
                    break
                fi
            else
                log "$SCRIPT_NAME" "    ↳ ERROR: Failed to upload ${PREFIX_TEXT}chunk $CHUNK_NAME"
                log "$SCRIPT_NAME" "    ↳ Output: $CHUNK_OUTPUT"
                UPLOAD_SUCCESS=false
                break
            fi
        fi
        
        CHUNK_NUM=$((CHUNK_NUM + 1))
    done <<< "$CHUNK_FILES"
}

# ============================================================================
# FILE PROCESSING
# ============================================================================

# Process a large file (>= MAX_FILE_SIZE_GB)
# Args: $1=filepath, $2=filename, $3=file_size
process_large_file() {
    local FILEPATH="$1"
    local FILENAME="$2"
    local FILE_SIZE="$3"
    
    local FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $FILE_SIZE/1073741824}")
    log "$SCRIPT_NAME" "  ↳ File is large (${FILE_SIZE_GB}GB >= ${MAX_FILE_SIZE_GB}GB), splitting into chunks..."
    
    # Create tmp directory relative to file's directory
    local FILEDIR=$(dirname "$FILEPATH")
    local TMP_DIR="${FILEDIR}/tmp"
    mkdir -p "$TMP_DIR"
    
    # Check if manifest already exists (from previous split)
    local MANIFEST_FILE="${TMP_DIR}/${FILENAME}.manifest"
    local CHUNK_PREFIX="${TMP_DIR}/${FILENAME}.part"
    
    if [ -f "$MANIFEST_FILE" ]; then
        # Manifest exists - read it to get expected chunk list
        log "$SCRIPT_NAME" "  ↳ Found existing manifest, reading expected chunk list..."
        
        # Extract chunk filenames from manifest
        local EXPECTED_CHUNKS=$(grep -o '"filename": "[^"]*"' "$MANIFEST_FILE" | sed 's/"filename": "\([^"]*\)"/\1/')
        local EXPECTED_CHUNK_COUNT=$(grep -o '"chunk_count": [0-9]*' "$MANIFEST_FILE" | grep -o '[0-9]*')
        
        if [ -z "$EXPECTED_CHUNK_COUNT" ] || [ -z "$EXPECTED_CHUNKS" ]; then
            log "$SCRIPT_NAME" "  ↳ ERROR: Could not read chunk information from existing manifest"
            log "$SCRIPT_NAME" "  ↳ Recreating manifest..."
            rm -f "$MANIFEST_FILE"
        else
            # Verify all expected chunks exist on disk
            local MISSING_CHUNKS=""
            while IFS= read -r CHUNK_NAME; do
                [ -z "$CHUNK_NAME" ] && continue
                local CHUNK_PATH="${TMP_DIR}/${CHUNK_NAME}"
                if [ ! -f "$CHUNK_PATH" ]; then
                    MISSING_CHUNKS="${MISSING_CHUNKS}${CHUNK_NAME} "
                fi
            done <<< "$EXPECTED_CHUNKS"
            
            if [ -n "$MISSING_CHUNKS" ]; then
                log "$SCRIPT_NAME" "  ↳ ERROR: Missing chunks from manifest: $MISSING_CHUNKS"
                log "$SCRIPT_NAME" "  ↳ Cannot proceed - chunks may have been deleted"
                return 1
            fi
            
            # Build CHUNK_FILES list from manifest order
            CHUNK_FILES=""
            while IFS= read -r CHUNK_NAME; do
                [ -z "$CHUNK_NAME" ] && continue
                CHUNK_FILES="${CHUNK_FILES}${TMP_DIR}/${CHUNK_NAME}\n"
            done <<< "$EXPECTED_CHUNKS"
            CHUNK_FILES=$(echo -e "$CHUNK_FILES" | grep -v '^$')
            CHUNK_COUNT="$EXPECTED_CHUNK_COUNT"
            
            log "$SCRIPT_NAME" "  ↳ Using existing manifest with $CHUNK_COUNT chunk(s)"
            # Don't recreate manifest - use existing one
        fi
    fi
    
    # If no manifest exists (or it was invalid), create chunks and manifest
    if [ ! -f "$MANIFEST_FILE" ]; then
        CHUNK_FILES=$(ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
        
        if [ -z "$CHUNK_FILES" ]; then
            # No chunks found, split the file
            if ! split_file "$FILEPATH" "$CHUNK_PREFIX"; then
                return 1
            fi
            # Re-find chunk files after splitting
            CHUNK_FILES=$(ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
        else
            log "$SCRIPT_NAME" "  ↳ Using existing chunks (file was already split)"
        fi
        
        CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
        
        # Create manifest immediately after split/discovery (proof of complete split)
        create_initial_manifest "$MANIFEST_FILE" "$FILENAME" "$FILE_SIZE" "$CHUNK_COUNT" "$CHUNK_FILES" false
    fi
    
    # Ensure CHUNK_COUNT is set if we used existing manifest (should already be set, but double-check)
    if [ -z "$CHUNK_COUNT" ]; then
        CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
    fi
    
    log "$SCRIPT_NAME" "  ↳ Found $CHUNK_COUNT chunk(s), checking upload status..."
    
    # Upload chunks
    upload_chunks "$CHUNK_FILES" false
    
    # Update and upload manifest if all chunks uploaded successfully
    if [ "$UPLOAD_SUCCESS" = true ]; then
        create_final_manifest "$MANIFEST_FILE" "$FILENAME" "$FILE_SIZE" "$CHUNK_COUNT" "$MANIFEST_CONTENT" false
        if ! upload_manifest "$MANIFEST_FILE" "$CHUNK_PREFIX" "$CHUNK_COUNT"; then
            log "$SCRIPT_NAME" "  ↳ ERROR: All chunks uploaded but manifest upload failed"
            log "$SCRIPT_NAME" "  ↳ Keeping chunks and manifest for retry on next run"
        fi
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload all chunks"
        log "$SCRIPT_NAME" "  ↳ Keeping chunks and manifest for retry on next run"
        # Don't delete chunks or manifest - they will be retried on next run
        # Either via process_large_file (if original exists) or process_orphaned_chunks (if original deleted)
    fi
}

# Process a small file (< MAX_FILE_SIZE_GB)
# Args: $1=filepath, $2=filename
process_small_file() {
    local FILEPATH="$1"
    local FILENAME="$2"
    
    log "$SCRIPT_NAME" "  ↳ Uploading: $FILENAME"
    
    # Upload the file normally
    local UPLOAD_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1)
    
    # Check if upload was successful
    if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        log "$SCRIPT_NAME" "  ↳ SUCCESS: $FILENAME uploaded successfully"
        
        # Extract and log the file hash if available
        local FILEHASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$FILEHASH" ]; then
            log "$SCRIPT_NAME" "  ↳ File hash: $FILEHASH"
        fi
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Upload failed for $FILENAME"
        log "$SCRIPT_NAME" "  ↳ Output: $UPLOAD_OUTPUT"
    fi
}

# Process all files in the archive directory
process_archive_files() {
    log "$SCRIPT_NAME" "Scanning for snapshot files older than 15 minutes..."
    
    find "$ARCHIVE_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tar.zstd" \) -mmin +15 2>/dev/null | while read -r FILEPATH; do
        local FILENAME=$(basename "$FILEPATH")
        
        log "$SCRIPT_NAME" "Found file: $FILENAME"
        
        # Check if file is already uploaded
        if echo "$UPLOADED_FILES" | grep -q "^$FILENAME "; then
            log "$SCRIPT_NAME" "  ↳ SKIP: $FILENAME already uploaded to Stratos"
            continue
        fi
        
        # Check file size - split if >= MAX_FILE_SIZE_GB, otherwise upload normally
        local FILE_SIZE=$(stat -c%s "$FILEPATH" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -ge "$MAX_FILE_SIZE_BYTES" ]; then
            if [ "$PROCESS_LARGE_FILES" = "true" ]; then
                process_large_file "$FILEPATH" "$FILENAME" "$FILE_SIZE"
            else
                log "$SCRIPT_NAME" "  ↳ SKIP: Large file processing is disabled (PROCESS_LARGE_FILES=false)"
            fi
        else
            process_small_file "$FILEPATH" "$FILENAME"
        fi
        
        log "$SCRIPT_NAME" ""
    done
}

# ============================================================================
# ORPHANED CHUNK PROCESSING
# ============================================================================

# Calculate total size from chunk files
# Args: $1=chunk_files (newline separated)
# Prints: total size in bytes
calculate_chunks_total_size() {
    local CHUNK_FILES="$1"
    local TOTAL_SIZE=0
    
    while IFS= read -r CHUNK_FILE; do
        [ -z "$CHUNK_FILE" ] && continue
        local CHUNK_SIZE=$(stat -c%s "$CHUNK_FILE" 2>/dev/null || stat -f%z "$CHUNK_FILE" 2>/dev/null || echo "0")
        TOTAL_SIZE=$((TOTAL_SIZE + CHUNK_SIZE))
    done <<< "$CHUNK_FILES"
    
    echo "$TOTAL_SIZE"
}

# Process a single set of orphaned chunks
# Args: $1=filename (base name without .part suffix)
process_orphaned_chunk_set() {
    local FILENAME="$1"
    local ORIGINAL_FILE="${ARCHIVE_DIR}/${FILENAME}"
    
    # Skip if original file still exists (already processed in main loop)
    if [ -f "$ORIGINAL_FILE" ]; then
        return 0
    fi
    
    # Check if manifest already exists on Stratos (already completed)
    if echo "$UPLOADED_FILES" | grep -q "^${FILENAME}.manifest "; then
        log "$SCRIPT_NAME" "  ↳ SKIP: Manifest for orphaned $FILENAME already exists on Stratos"
        return 0
    fi
    
    # Get list of chunks for this file
    local CHUNK_PREFIX="${ARCHIVE_DIR}/tmp/${FILENAME}.part"
    local CHUNK_FILES=$(ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
    
    if [ -z "$CHUNK_FILES" ]; then
        return 0
    fi
    
    local MANIFEST_FILE="${ARCHIVE_DIR}/tmp/${FILENAME}.manifest"
    
    # CRITICAL: Only process orphaned chunks if they have a local manifest
    # The manifest proves the split was complete. Without it, chunks may be incomplete.
    if [ ! -f "$MANIFEST_FILE" ]; then
        log "$SCRIPT_NAME" "  ↳ SKIP: No manifest found for orphaned chunks of $FILENAME (split may be incomplete)"
        return 0
    fi
    
    # Verify chunk count matches what manifest says
    local ACTUAL_CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
    local EXPECTED_CHUNK_COUNT=$(grep -o '"chunk_count": [0-9]*' "$MANIFEST_FILE" | grep -o '[0-9]*')
    
    if [ -z "$EXPECTED_CHUNK_COUNT" ]; then
        log "$SCRIPT_NAME" "  ↳ SKIP: Could not read chunk_count from manifest for $FILENAME"
        return 0
    fi
    
    if [ "$ACTUAL_CHUNK_COUNT" -ne "$EXPECTED_CHUNK_COUNT" ]; then
        log "$SCRIPT_NAME" "  ↳ SKIP: Chunk count mismatch for $FILENAME (expected: $EXPECTED_CHUNK_COUNT, found: $ACTUAL_CHUNK_COUNT)"
        log "$SCRIPT_NAME" "  ↳ Some chunks may be missing or corrupted. Manual intervention required."
        return 0
    fi
    
    log "$SCRIPT_NAME" "Found orphaned chunks for: $FILENAME"
    log "$SCRIPT_NAME" "  ↳ Found local manifest (split was complete)"
    log "$SCRIPT_NAME" "  ↳ Verified chunk count: $ACTUAL_CHUNK_COUNT chunks"
    
    local CHUNK_COUNT="$ACTUAL_CHUNK_COUNT"
    
    # Calculate total size from chunks
    local TOTAL_SIZE=$(calculate_chunks_total_size "$CHUNK_FILES")
    
    log "$SCRIPT_NAME" "  ↳ Found $CHUNK_COUNT orphaned chunk(s), checking upload status..."
    
    # Re-fetch uploaded files list to get latest state
    UPLOADED_FILES=$(rpc_list "$SCRIPT_NAME")
    
    # Upload chunks
    upload_chunks "$CHUNK_FILES" true
    
    # Update and upload manifest if all chunks uploaded successfully
    if [ "$UPLOAD_SUCCESS" = true ]; then
        create_final_manifest "$MANIFEST_FILE" "$FILENAME" "$TOTAL_SIZE" "$CHUNK_COUNT" "$MANIFEST_CONTENT" true
        
        log "$SCRIPT_NAME" "  ↳ Uploading manifest for orphaned chunks: ${FILENAME}.manifest"
        local MANIFEST_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$MANIFEST_FILE" 2>&1)
        
        if echo "$MANIFEST_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
            local MANIFEST_HASH=$(echo "$MANIFEST_OUTPUT" | grep "File " | awk '{print $3}')
            if [ -n "$MANIFEST_HASH" ]; then
                log "$SCRIPT_NAME" "  ↳ SUCCESS: All $CHUNK_COUNT orphaned chunk(s) and manifest uploaded (manifest hash: $MANIFEST_HASH)"
            else
                log "$SCRIPT_NAME" "  ↳ WARNING: Manifest uploaded but hash extraction failed"
                log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
            fi
            # Cleanup local chunks and manifest (keep tmp directory)
            rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
        else
            log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload manifest file for orphaned chunks"
            log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
        fi
    else
        log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload all orphaned chunks, keeping for retry"
    fi
    
    log "$SCRIPT_NAME" ""
}

# Process all orphaned chunks in /tmp directories
process_orphaned_chunks() {
    log "$SCRIPT_NAME" "Checking for orphaned chunks in /tmp directories..."
    
    if [ ! -d "${ARCHIVE_DIR}/tmp" ]; then
        return 0
    fi
    
    # Find all chunk files and extract unique base filenames
    find "${ARCHIVE_DIR}/tmp" -type f -name "*.part*" 2>/dev/null | sed 's/\.part[a-z]*$//' | sort -u | while read -r CHUNK_BASE; do
        local FILENAME=$(basename "$CHUNK_BASE")
        process_orphaned_chunk_set "$FILENAME"
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Acquire lock to prevent concurrent executions
    acquire_lock
    
    log "$SCRIPT_NAME" "Starting snapshot upload monitor..."
    
    # Log configuration
    log "$SCRIPT_NAME" "Configuration:"
    log "$SCRIPT_NAME" "  ARCHIVE_DIR: $ARCHIVE_DIR"
    log "$SCRIPT_NAME" "  MAX_FILE_SIZE_GB: $MAX_FILE_SIZE_GB"
    log "$SCRIPT_NAME" "  PROCESS_LARGE_FILES: $PROCESS_LARGE_FILES"
    log "$SCRIPT_NAME" "  PROCESS_ORPHANED_CHUNKS: $PROCESS_ORPHANED_CHUNKS"
    
    # Check if required environment variables are set
    validate_rpc_env "$SCRIPT_NAME"
    
    # Verify archive directory exists
    if [ ! -d "$ARCHIVE_DIR" ]; then
        log "$SCRIPT_NAME" "ERROR: Archive directory $ARCHIVE_DIR does not exist"
        exit 1
    fi
    
    # Get list of already uploaded files from Stratos
    UPLOADED_FILES=$(rpc_list "$SCRIPT_NAME")
    
    # Process archive files
    process_archive_files
    
    # Process orphaned chunks (if enabled)
    if [ "$PROCESS_ORPHANED_CHUNKS" = "true" ]; then
        process_orphaned_chunks
    else
        log "$SCRIPT_NAME" "Orphaned chunk processing is disabled (PROCESS_ORPHANED_CHUNKS=false)"
    fi
    
    log "$SCRIPT_NAME" "Snapshot upload monitor completed"
}

# Run main function
main
