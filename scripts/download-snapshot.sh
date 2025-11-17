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
    echo "Usage: $0 <filename|latest>"
    echo "  filename - Download a specific file by name"
    echo "  latest   - Download the most recent file (by timestamp)"
    exit 1
fi

FILENAME="$1"
WORK_DIR="/sds"

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
else
    # Get file list and extract hash for matching filename
    FILEHASH=$(echo "$FILE_LIST" | \
        grep -v "^\[DEBUG\]" | \
        grep -F "$FILENAME" | \
        awk '{print $2}')
    
    # Check if file was found
    if [ -z "$FILEHASH" ]; then
        echo "Error: File '$FILENAME' not found in list"
        exit 1
    fi
fi

# Check if file already exists
if docker exec -u sds sds-node test -f "$WORK_DIR/download/$FILENAME" 2>/dev/null; then
    echo "ℹ File already exists: $WORK_DIR/download/$FILENAME"
    echo "Skipping download (file already present)"
    echo "File location: $WORK_DIR/download/$FILENAME"
    exit 0
fi

# Download the file with retry logic
echo "Downloading $FILENAME (hash: $FILEHASH)..."

MAX_RETRIES=5
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo ""
        echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
    fi
    
    DOWNLOAD_OUTPUT=$(docker exec -u sds -it sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}" 2>&1)
    echo "$DOWNLOAD_OUTPUT"
    
    # Success check: download succeeds when output does NOT contain "return:  -5"
    if ! echo "$DOWNLOAD_OUTPUT" | grep -q "return:  -5"; then
        DOWNLOAD_SUCCESS=true
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "⚠ Download failed (response code: -5), retrying in 2 seconds..."
            sleep 2
        else
            echo ""
            echo "✗ Download failed after $MAX_RETRIES attempts (response code: -5)"
            exit 1
        fi
    fi
done

if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo ""
    echo "✓ Download completed successfully"
    echo "File location: ./download/$FILENAME"
fi

