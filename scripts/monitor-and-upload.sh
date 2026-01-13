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
MAX_FILE_SIZE_GB=50
MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_GB * 1024 * 1024 * 1024))  # 50GB in bytes

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
    
    # Check file size - split if >= 50GB, otherwise upload normally
    FILE_SIZE=$(stat -c%s "$FILEPATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -ge "$MAX_FILE_SIZE_BYTES" ]; then
        FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $FILE_SIZE/1073741824}")
        log "$SCRIPT_NAME" "  ↳ File is large (${FILE_SIZE_GB}GB >= ${MAX_FILE_SIZE_GB}GB), splitting into chunks..."
        
        # Create tmp directory relative to file's directory
        FILEDIR=$(dirname "$FILEPATH")
        TMP_DIR="${FILEDIR}/tmp"
        mkdir -p "$TMP_DIR"
        
        # Split the file into chunks in tmp directory
        CHUNK_PREFIX="${TMP_DIR}/${FILENAME}.part"
        if ! split -b "$MAX_FILE_SIZE_BYTES" "$FILEPATH" "$CHUNK_PREFIX"; then
            log "$SCRIPT_NAME" "  ↳ ERROR: Failed to split file $FILENAME"
            continue
        fi
        
        # Find all chunk files
        CHUNK_FILES=$(ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
        CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
        MANIFEST_CONTENT=""
        UPLOAD_SUCCESS=true
        
        log "$SCRIPT_NAME" "  ↳ Created $CHUNK_COUNT chunk(s), uploading..."
        
        # Upload each chunk
        CHUNK_NUM=1
        while IFS= read -r CHUNK_FILE; do
            [ -z "$CHUNK_FILE" ] && continue
            CHUNK_NAME=$(basename "$CHUNK_FILE")
            log "$SCRIPT_NAME" "    ↳ Uploading chunk $CHUNK_NUM/$CHUNK_COUNT: $CHUNK_NAME"
            
            CHUNK_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$CHUNK_FILE" 2>&1)
            
            if echo "$CHUNK_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
                CHUNK_HASH=$(echo "$CHUNK_OUTPUT" | grep "File " | awk '{print $3}')
                if [ -n "$CHUNK_HASH" ]; then
                    if [ -n "$MANIFEST_CONTENT" ]; then
                        MANIFEST_CONTENT="${MANIFEST_CONTENT},\n"
                    fi
                    MANIFEST_CONTENT="${MANIFEST_CONTENT}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": \"${CHUNK_HASH}\"}"
                    log "$SCRIPT_NAME" "    ↳ SUCCESS: $CHUNK_NAME uploaded (hash: $CHUNK_HASH)"
                fi
            else
                log "$SCRIPT_NAME" "    ↳ ERROR: Failed to upload chunk $CHUNK_NAME"
                log "$SCRIPT_NAME" "    ↳ Output: $CHUNK_OUTPUT"
                UPLOAD_SUCCESS=false
                break
            fi
            
            CHUNK_NUM=$((CHUNK_NUM + 1))
        done <<< "$CHUNK_FILES"
        
        # Create and upload manifest if all chunks uploaded successfully
        if [ "$UPLOAD_SUCCESS" = true ]; then
            MANIFEST_FILE="${TMP_DIR}/${FILENAME}.manifest"
            cat > "$MANIFEST_FILE" <<EOF
{
  "original_filename": "$FILENAME",
  "original_size": $FILE_SIZE,
  "chunk_count": $CHUNK_COUNT,
  "chunk_size": $MAX_FILE_SIZE_BYTES,
  "chunks": [
$(echo -e "$MANIFEST_CONTENT")
  ]
}
EOF
            
            log "$SCRIPT_NAME" "  ↳ Uploading manifest file: ${FILENAME}.manifest"
            MANIFEST_OUTPUT=$(rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$MANIFEST_FILE" 2>&1)
            
            if echo "$MANIFEST_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
                MANIFEST_HASH=$(echo "$MANIFEST_OUTPUT" | grep "File " | awk '{print $3}')
                log "$SCRIPT_NAME" "  ↳ SUCCESS: All $CHUNK_COUNT chunk(s) and manifest uploaded (manifest hash: $MANIFEST_HASH)"
                # Cleanup local chunks and manifest (keep tmp directory)
                rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
            else
                log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload manifest file"
                log "$SCRIPT_NAME" "  ↳ Output: $MANIFEST_OUTPUT"
                rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE"
            fi
        else
            log "$SCRIPT_NAME" "  ↳ ERROR: Failed to upload all chunks, cleaning up..."
            rm -f "${CHUNK_PREFIX}"*
        fi
    else
        log "$SCRIPT_NAME" "  ↳ Uploading: $FILENAME"
        
        # Upload the file normally
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
    fi
    
    log "$SCRIPT_NAME" ""
done

log "$SCRIPT_NAME" "Snapshot upload monitor completed"

