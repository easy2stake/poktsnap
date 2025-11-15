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

# Check peer registration status
echo "Checking peer registration status..."
RP_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" rp 2>&1)

if echo "$RP_OUTPUT" | grep -q "return: SUCCESS"; then
    echo "✓ Peer registered successfully"
elif echo "$RP_OUTPUT" | grep -q "return:  -10"; then
    echo "✓ Peer already registered"
else
    echo "Error: Failed to register peer"
    echo "$RP_OUTPUT"
    exit 1
fi
echo ""

# Get the full file list
FILE_LIST=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list)

if [ "$FILENAME" = "latest" ]; then
    # Find the file with the highest timestamp (4th column)
    # Filter for tar files only and sort by timestamp
    MOST_RECENT_FILE=$(echo "$FILE_LIST" | \
        grep ".tar" | \
        awk 'NF>=4 {print $0}' | \
        sort -k4 -n -r | \
        head -n 1)
    
    if [ -z "$MOST_RECENT_FILE" ]; then
        echo "Error: No files found in list"
        exit 1
    fi
    
    FILENAME=$(echo "$MOST_RECENT_FILE" | awk '{print $1}')
    FILEHASH=$(echo "$MOST_RECENT_FILE" | awk '{print $2}')
    TIMESTAMP=$(echo "$MOST_RECENT_FILE" | awk '{print $4}')
    
    echo "Latest file found: $FILENAME (timestamp: $TIMESTAMP)"
else
    # Get file list and extract hash for matching filename
    FILEHASH=$(echo "$FILE_LIST" | \
        grep -F "$FILENAME" | \
        awk '{print $2}')
    
    # Check if file was found
    if [ -z "$FILEHASH" ]; then
        echo "Error: File '$FILENAME' not found in list"
        exit 1
    fi
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
    
    # Check if download was successful
    if echo "$DOWNLOAD_OUTPUT" | grep -q "return:  -5"; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "⚠ Download failed (response code: -5), retrying..."
            sleep 2
        else
            echo "✗ Download failed after $MAX_RETRIES attempts (response code: -5)"
            exit 1
        fi
    else
        DOWNLOAD_SUCCESS=true
        break
    fi
done

if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo ""
    echo "✓ Download completed successfully"
fi

