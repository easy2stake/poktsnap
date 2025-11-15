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

# Check if file exists
if [ ! -f "$FILEPATH" ]; then
    echo "Error: File '$FILEPATH' not found"
    exit 1
fi

echo "Uploading file: $FILEPATH"
echo ""

# Upload the file
UPLOAD_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1)
echo "$UPLOAD_OUTPUT"

# Check if upload was successful
if echo "$UPLOAD_OUTPUT" | grep -q "has been sent to destinations"; then
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

