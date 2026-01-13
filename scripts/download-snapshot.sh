#!/usr/bin/env bash

# Load configuration from .env file
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Configuration
WORK_DIR="/sds"
MAX_RETRIES=5

# ============================================================================
# Helper Functions
# ============================================================================

# Download a single file with retry logic
# Usage: download_file "filename" "filehash" "output_path"
download_file() {
    local FILENAME="$1"
    local FILEHASH="$2"
    local OUTPUT_PATH="$3"
    local RETRY_COUNT=0
    local DOWNLOAD_SUCCESS=false
    
    echo "Downloading $FILENAME (hash: $FILEHASH)..."
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
        fi
        
        DOWNLOAD_OUTPUT=$(docker exec -u sds -it sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}" 2>&1)
        
        # Success check: download succeeds when output does NOT contain "return:  -5"
        if ! echo "$DOWNLOAD_OUTPUT" | grep -q "return:  -5"; then
            DOWNLOAD_SUCCESS=true
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "⚠ Download failed (response code: -5), retrying in 2 seconds..."
                sleep 2
            fi
        fi
    done
    
    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        return 0
    else
        echo "✗ Download failed after $MAX_RETRIES attempts"
        return 1
    fi
}

# Check if a manifest file exists for the given filename
# Usage: check_for_manifest "filename"
# Returns: 0 if manifest exists, 1 if not
check_for_manifest() {
    local BASE_FILENAME="$1"
    local MANIFEST_NAME="${BASE_FILENAME}.manifest"
    
    if echo "$FILE_LIST" | grep -v "^\[DEBUG\]" | grep -q "^${MANIFEST_NAME} "; then
        return 0
    else
        return 1
    fi
}

# Download and parse the manifest file
# Usage: download_manifest "filename"
# Sets global variables: MANIFEST_FILE, ORIGINAL_SIZE, CHUNK_COUNT
download_manifest() {
    local BASE_FILENAME="$1"
    local MANIFEST_NAME="${BASE_FILENAME}.manifest"
    
    echo ""
    echo "=========================================="
    echo "Chunked file detected!"
    echo "=========================================="
    echo ""
    
    # Get manifest hash
    local MANIFEST_HASH=$(echo "$FILE_LIST" | grep -v "^\[DEBUG\]" | grep "^${MANIFEST_NAME} " | awk '{print $2}')
    
    if [ -z "$MANIFEST_HASH" ]; then
        echo "Error: Manifest file not found"
        return 1
    fi
    
    # Download manifest
    echo "Step 1: Downloading manifest..."
    if ! download_file "$MANIFEST_NAME" "$MANIFEST_HASH" "$WORK_DIR/download/$MANIFEST_NAME"; then
        return 1
    fi
    
    # Parse manifest JSON
    MANIFEST_FILE="$WORK_DIR/download/$MANIFEST_NAME"
    
    # Extract values from manifest using docker exec
    ORIGINAL_SIZE=$(docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -o '"original_size": [0-9]*' | awk '{print $2}')
    CHUNK_COUNT=$(docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -o '"chunk_count": [0-9]*' | awk '{print $2}')
    
    echo "✓ Manifest downloaded"
    echo "  Original file size: $(awk "BEGIN {printf \"%.2f GB\", $ORIGINAL_SIZE/1073741824}")"
    echo "  Number of chunks: $CHUNK_COUNT"
    
    return 0
}

# Download all chunks from the manifest
# Usage: download_chunks "base_filename"
download_chunks() {
    local BASE_FILENAME="$1"
    local CHUNK_NUM=0
    
    echo ""
    echo "Step 2: Downloading chunks..."
    echo ""
    
    # Parse chunks from manifest and download each one
    docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -o '"filename": "[^"]*"' | sed 's/"filename": "//;s/"//' | while read -r CHUNK_NAME; do
        CHUNK_NUM=$((CHUNK_NUM + 1))
        
        # Check if chunk already exists
        if docker exec -u sds sds-node test -f "$WORK_DIR/download/$CHUNK_NAME" 2>/dev/null; then
            echo "[$CHUNK_NUM/$CHUNK_COUNT] ℹ Chunk $CHUNK_NAME already exists, skipping..."
            continue
        fi
        
        # Get chunk hash from manifest
        CHUNK_HASH=$(docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -A1 "\"filename\": \"$CHUNK_NAME\"" | grep '"hash"' | sed 's/.*"hash": "//;s/".*//')
        
        if [ -z "$CHUNK_HASH" ]; then
            echo "Error: Could not find hash for chunk $CHUNK_NAME"
            return 1
        fi
        
        echo "[$CHUNK_NUM/$CHUNK_COUNT] Downloading chunk: $CHUNK_NAME"
        if ! download_file "$CHUNK_NAME" "$CHUNK_HASH" "$WORK_DIR/download/$CHUNK_NAME"; then
            echo "Error: Failed to download chunk $CHUNK_NAME"
            return 1
        fi
        echo "[$CHUNK_NUM/$CHUNK_COUNT] ✓ Downloaded successfully"
        echo ""
    done
    
    return 0
}

# Reassemble chunks into the original file
# Usage: reassemble_chunks "base_filename"
reassemble_chunks() {
    local BASE_FILENAME="$1"
    local OUTPUT_FILE="$WORK_DIR/download/$BASE_FILENAME"
    
    echo ""
    echo "Step 3: Reassembling chunks..."
    
    # Get list of chunk filenames from manifest in correct order
    local CHUNK_FILES=$(docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -o '"filename": "[^"]*"' | sed 's/"filename": "//;s/"//')
    
    # Build the cat command with all chunks in order
    local CHUNK_PATHS=""
    while read -r CHUNK_NAME; do
        CHUNK_PATHS="$CHUNK_PATHS $WORK_DIR/download/$CHUNK_NAME"
    done <<< "$CHUNK_FILES"
    
    # Concatenate all chunks into the final file
    if docker exec -u sds sds-node sh -c "cat $CHUNK_PATHS > $OUTPUT_FILE" 2>/dev/null; then
        echo "✓ Chunks reassembled successfully"
        return 0
    else
        echo "✗ Failed to reassemble chunks"
        return 1
    fi
}

# Verify the final file size matches expected size
# Usage: verify_file_size "filename" "expected_size"
verify_file_size() {
    local FILENAME="$1"
    local EXPECTED_SIZE="$2"
    local FILE_PATH="$WORK_DIR/download/$FILENAME"
    
    echo ""
    echo "Step 4: Verifying file integrity..."
    
    local ACTUAL_SIZE=$(docker exec -u sds sds-node stat -c%s "$FILE_PATH" 2>/dev/null)
    
    if [ "$ACTUAL_SIZE" = "$EXPECTED_SIZE" ]; then
        echo "✓ File size verified: $(awk "BEGIN {printf \"%.2f GB\", $ACTUAL_SIZE/1073741824}")"
        return 0
    else
        echo "✗ File size mismatch!"
        echo "  Expected: $(awk "BEGIN {printf \"%.2f GB\", $EXPECTED_SIZE/1073741824}") ($EXPECTED_SIZE bytes)"
        echo "  Actual: $(awk "BEGIN {printf \"%.2f GB\", $ACTUAL_SIZE/1073741824}") ($ACTUAL_SIZE bytes)"
        return 1
    fi
}

# Cleanup temporary files (chunks and manifest)
# Usage: cleanup_chunks "base_filename"
cleanup_chunks() {
    local BASE_FILENAME="$1"
    local MANIFEST_NAME="${BASE_FILENAME}.manifest"
    
    echo ""
    echo "Step 5: Cleaning up temporary files..."
    
    # Get list of chunk filenames from manifest
    local CHUNK_FILES=$(docker exec -u sds sds-node cat "$MANIFEST_FILE" | grep -o '"filename": "[^"]*"' | sed 's/"filename": "//;s/"//')
    
    # Delete each chunk
    while read -r CHUNK_NAME; do
        docker exec -u sds sds-node rm -f "$WORK_DIR/download/$CHUNK_NAME" 2>/dev/null
    done <<< "$CHUNK_FILES"
    
    # Delete manifest
    docker exec -u sds sds-node rm -f "$WORK_DIR/download/$MANIFEST_NAME" 2>/dev/null
    
    echo "✓ Temporary files cleaned up"
}

# ============================================================================
# Main Script Logic
# ============================================================================

# Check argument
if [ -z "$1" ]; then
    echo "Usage: $0 <filename|latest>"
    echo "  filename - Download a specific file by name"
    echo "  latest   - Download the most recent file (by timestamp)"
    exit 1
fi

FILENAME="$1"

# Get the full file list
FILE_LIST=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list)

# Filter out debug lines and get .tar files (exclude debug lines)
TAR_FILES=$(echo "$FILE_LIST" | grep -v "^\[DEBUG\]" | grep "\.tar" | awk 'NF>=4 {print $0}' | sort -k4 -n -r)

if [ "$FILENAME" = "latest" ]; then
    # Find the file with the highest timestamp (4th column)
    # Get the most recent file from already-filtered list
    MOST_RECENT_FILE=$(echo "$TAR_FILES" | head -n 1)
    
    if [ -z "$MOST_RECENT_FILE" ]; then
        echo "Error: No .tar files found in list"
        exit 1
    fi
    
    FILENAME=$(echo "$MOST_RECENT_FILE" | awk '{print $1}')
    FILEHASH=$(echo "$MOST_RECENT_FILE" | awk '{print $2}')
    TIMESTAMP=$(echo "$MOST_RECENT_FILE" | awk '{print $4}')
    
    echo "Latest file found: $FILENAME (timestamp: $TIMESTAMP)"
fi

# Check if file already exists
if docker exec -u sds sds-node test -f "$WORK_DIR/download/$FILENAME" 2>/dev/null; then
    echo "ℹ File already exists: ./sds-data/download/$FILENAME"
    echo "Skipping download (file already present)"
    echo "File location: ./sds-data/download/$FILENAME"
    exit 0
fi

# Check if this is a chunked file (manifest exists)
if check_for_manifest "$FILENAME"; then
    # ========================================================================
    # CHUNKED FILE DOWNLOAD
    # ========================================================================
    
    # Download and parse manifest
    if ! download_manifest "$FILENAME"; then
        echo "Error: Failed to download or parse manifest"
        exit 1
    fi
    
    # Download all chunks
    if ! download_chunks "$FILENAME"; then
        echo "Error: Failed to download chunks"
        exit 1
    fi
    
    # Reassemble chunks into original file
    if ! reassemble_chunks "$FILENAME"; then
        echo "Error: Failed to reassemble chunks"
        exit 1
    fi
    
    # Verify file integrity
    if ! verify_file_size "$FILENAME" "$ORIGINAL_SIZE"; then
        echo "Error: File integrity check failed"
        exit 1
    fi
    
    # Cleanup temporary files
    cleanup_chunks "$FILENAME"
    
    echo ""
    echo "=========================================="
    echo "✓ Download and reassembly completed!"
    echo "=========================================="
    echo "File location: ./sds-data/download/$FILENAME"
    
else
    # ========================================================================
    # REGULAR FILE DOWNLOAD
    # ========================================================================
    
    # Get file hash if not already set (for non-latest files)
    if [ -z "$FILEHASH" ]; then
        FILEHASH=$(echo "$FILE_LIST" | \
            grep -v "^\[DEBUG\]" | \
            grep -F "$FILENAME" | \
            awk '{print $2}')
        
        if [ -z "$FILEHASH" ]; then
            echo "Error: File '$FILENAME' not found in list"
            exit 1
        fi
    fi
    
    # Download the file with retry logic
    if download_file "$FILENAME" "$FILEHASH" "$WORK_DIR/download/$FILENAME"; then
        echo ""
        echo "✓ Download completed successfully"
        echo "File location: ./sds-data/download/$FILENAME"
    else
        exit 1
    fi
fi
