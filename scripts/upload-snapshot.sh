#!/usr/bin/env bash

# Load configuration from .env file
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Check argument
if [ -z "$1" ]; then
    echo "Usage: $0 <file-path>"
    echo "  file-path - Path to the file you want to upload"
    exit 1
fi

FILEPATH="$1"
MAX_FILE_SIZE_GB=50
MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_GB * 1024 * 1024 * 1024))  # 50GB in bytes

# Check if file exists inside the container
if ! docker exec -u sds sds-node test -f "$FILEPATH" 2>/dev/null; then
    echo "Error: File '$FILEPATH' not found inside container"
    exit 1
fi

# Check file size
FILE_SIZE=$(docker exec -u sds sds-node stat -c%s "$FILEPATH" 2>/dev/null || echo "0")
FILENAME=$(basename "$FILEPATH")

if [ "$FILE_SIZE" -ge "$MAX_FILE_SIZE_BYTES" ]; then
    FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $FILE_SIZE/1073741824}")
    echo "File is large (${FILE_SIZE_GB}GB >= ${MAX_FILE_SIZE_GB}GB), splitting into chunks..."
    echo ""
    
    # Create tmp directory relative to file's directory inside the container
    FILEDIR=$(dirname "$FILEPATH")
    TMP_DIR="${FILEDIR}/tmp"
    docker exec -u sds sds-node mkdir -p "$TMP_DIR" 2>&1
    
    # Check if chunks already exist
    CHUNK_PREFIX="${TMP_DIR}/${FILENAME}.part"
    CHUNK_FILES=$(docker exec -u sds sds-node ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
    
    if [ -z "$CHUNK_FILES" ]; then
        # No chunks found, split the file
        echo "Splitting file into chunks..."
        if ! docker exec -u sds sds-node split -b "$MAX_FILE_SIZE_BYTES" "$FILEPATH" "$CHUNK_PREFIX" 2>&1; then
            echo "Error: Failed to split file $FILENAME"
            exit 1
        fi
        # Re-find chunk files after splitting
        CHUNK_FILES=$(docker exec -u sds sds-node ls -1 "${CHUNK_PREFIX}"* 2>/dev/null | sort)
    else
        echo "Using existing chunks (file was already split)"
    fi
    CHUNK_COUNT=$(echo "$CHUNK_FILES" | wc -l | tr -d ' ')
    MANIFEST_CONTENT=""
    UPLOAD_SUCCESS=true
    
    # Get list of already uploaded files to check for existing chunks
    echo "Checking upload status..."
    UPLOADED_FILES=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)
    echo ""
    
    echo "Found $CHUNK_COUNT chunk(s), uploading..."
    echo ""
    
    # Upload each chunk (skip if already uploaded)
    CHUNK_NUM=1
    while IFS= read -r CHUNK_FILE; do
        [ -z "$CHUNK_FILE" ] && continue
        CHUNK_NAME=$(basename "$CHUNK_FILE")
        
        # Check if chunk is already uploaded
        if echo "$UPLOADED_FILES" | grep -q "^${CHUNK_NAME} "; then
            echo "ℹ SKIP: $CHUNK_NAME already uploaded"
            # Get hash from uploaded files list for manifest
            CHUNK_HASH=$(echo "$UPLOADED_FILES" | grep "^${CHUNK_NAME} " | awk '{print $2}')
            if [ -n "$CHUNK_HASH" ]; then
                if [ -n "$MANIFEST_CONTENT" ]; then
                    MANIFEST_CONTENT="${MANIFEST_CONTENT},\n"
                fi
                MANIFEST_CONTENT="${MANIFEST_CONTENT}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": \"${CHUNK_HASH}\"}"
            fi
        else
            echo "Uploading chunk $CHUNK_NUM/$CHUNK_COUNT: $CHUNK_NAME"
            
            CHUNK_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$CHUNK_FILE" 2>&1 | tee /dev/tty)
            
            if echo "$CHUNK_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
                CHUNK_HASH=$(echo "$CHUNK_OUTPUT" | grep "File " | awk '{print $3}')
                if [ -n "$CHUNK_HASH" ]; then
                    if [ -n "$MANIFEST_CONTENT" ]; then
                        MANIFEST_CONTENT="${MANIFEST_CONTENT},\n"
                    fi
                    MANIFEST_CONTENT="${MANIFEST_CONTENT}    {\"filename\": \"${CHUNK_NAME}\", \"hash\": \"${CHUNK_HASH}\"}"
                    echo "✓ Chunk $CHUNK_NUM/$CHUNK_COUNT uploaded successfully (hash: $CHUNK_HASH)"
                fi
            else
                echo "✗ Failed to upload chunk $CHUNK_NUM/$CHUNK_COUNT"
                UPLOAD_SUCCESS=false
                break
            fi
        fi
        
        echo ""
        CHUNK_NUM=$((CHUNK_NUM + 1))
    done <<< "$CHUNK_FILES"
    
    # Create and upload manifest if all chunks uploaded successfully
    if [ "$UPLOAD_SUCCESS" = true ]; then
        MANIFEST_FILE="${TMP_DIR}/${FILENAME}.manifest"
        docker exec -u sds sds-node bash -c "cat > \"$MANIFEST_FILE\" <<'EOF'
{
  \"original_filename\": \"$FILENAME\",
  \"original_size\": $FILE_SIZE,
  \"chunk_count\": $CHUNK_COUNT,
  \"chunk_size\": $MAX_FILE_SIZE_BYTES,
  \"chunks\": [
$(echo -e "$MANIFEST_CONTENT")
  ]
}
EOF"
        
        echo "Uploading manifest file: ${FILENAME}.manifest"
        MANIFEST_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$MANIFEST_FILE" 2>&1 | tee /dev/tty)
        
        if echo "$MANIFEST_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
            MANIFEST_HASH=$(echo "$MANIFEST_OUTPUT" | grep "File " | awk '{print $3}')
            echo ""
            echo "✓ All $CHUNK_COUNT chunk(s) and manifest uploaded successfully"
            echo "Manifest hash: $MANIFEST_HASH"
            # Cleanup local chunks and manifest (keep tmp directory)
            docker exec -u sds sds-node rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE" 2>/dev/null
        else
            echo ""
            echo "✗ Failed to upload manifest file"
            docker exec -u sds sds-node rm -f "${CHUNK_PREFIX}"* "$MANIFEST_FILE" 2>/dev/null
            exit 1
        fi
    else
        echo ""
        echo "✗ Failed to upload all chunks, cleaning up..."
        docker exec -u sds sds-node rm -f "${CHUNK_PREFIX}"* 2>/dev/null
        exit 1
    fi
else
    echo "Uploading file: $FILEPATH"
    echo ""
    
    # Upload the file normally (stream output to terminal while capturing for success check)
    UPLOAD_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1 | tee /dev/tty)
    
    # Check if upload was successful
    if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        echo ""
        echo "✓ Upload completed successfully"
        
        # Extract and display the file hash
        FILEHASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$FILEHASH" ]; then
            echo "File hash: $FILEHASH"
        fi
    else
        echo ""
        echo "✗ Upload may have failed. Please check the output above."
        exit 1
    fi
fi

